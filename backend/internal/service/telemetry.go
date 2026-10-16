package service

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"strings"

	"road_pulse/backend/internal/models"
	"road_pulse/backend/internal/osrm"

	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	MinSpeedKMH   = 20.0
	BaseSpeedKMH  = 20.0
	ClusterEpsDeg = 0.0003
)

type TelemetryService struct {
	pool *pgxpool.Pool
	osrm *osrm.Client
}

func NewTelemetryService(pool *pgxpool.Pool, osrmClient *osrm.Client) *TelemetryService {
	return &TelemetryService{
		pool: pool,
		osrm: osrmClient,
	}
}

func (s *TelemetryService) CalculateNormalizedForce(bumpForce, speedKMH float64) float64 {
	safeSpeed := math.Max(speedKMH, BaseSpeedKMH)
	return bumpForce * (BaseSpeedKMH / safeSpeed)
}

func (s *TelemetryService) ResolveLocationWKT(ctx context.Context, payload *models.TelemetryPayload) (string, string) {
	if len(payload.Trajectory) > 2 {
		if wkt, geomType, ok := s.osrm.Match(ctx, payload.Trajectory); ok {
			if payload.DefectType == "rough_road" && geomType == "LineString" {
				return wkt, geomType
			}
			// Извлечение первой точки из LINESTRING в случае pothole
			if geomType == "LineString" && strings.HasPrefix(wkt, "LINESTRING(") {
				inside := strings.TrimSuffix(strings.TrimPrefix(wkt, "LINESTRING("), ")")
				pts := strings.Split(inside, ",")
				if len(pts) > 0 {
					return fmt.Sprintf("POINT(%s)", strings.TrimSpace(pts[0])), "Point"
				}
			}
			return wkt, geomType
		}
	}

	snappedLat, snappedLon := s.osrm.Nearest(ctx, payload.Latitude, payload.Longitude)
	return fmt.Sprintf("POINT(%f %f)", snappedLon, snappedLat), "Point"
}

func (s *TelemetryService) SaveTelemetry(ctx context.Context, payload *models.TelemetryPayload) (*models.TelemetryResponse, error) {
	if payload.DefectType == "" {
		payload.DefectType = "pothole"
	}
	if payload.InfrastructureType == "" {
		payload.InfrastructureType = "road"
	}

	locationWKT, geomType := s.ResolveLocationWKT(ctx, payload)
	normalizedForce := s.CalculateNormalizedForce(payload.BumpForce, payload.SpeedKMH)

	query := `
		INSERT INTO telemetry (
			user_id, location, speed_kmh, bump_force, defect_type, infrastructure_type
		) VALUES (
			$1, ST_GeomFromText($2, 4326), $3, $4, $5, $6
		)
		RETURNING id, ST_Y(ST_Centroid(location)), ST_X(ST_Centroid(location));
	`

	var id int64
	var snappedLat, snappedLon float64

	err := s.pool.QueryRow(ctx, query,
		payload.UserID,
		locationWKT,
		payload.SpeedKMH,
		normalizedForce,
		payload.DefectType,
		payload.InfrastructureType,
	).Scan(&id, &snappedLat, &snappedLon)
	if err != nil {
		return nil, fmt.Errorf("ошибка вставки в БД: %w", err)
	}

	return &models.TelemetryResponse{
		Status:             "ok",
		ID:                 id,
		SnappedLat:         snappedLat,
		SnappedLon:         snappedLon,
		BumpForce:          normalizedForce,
		DefectType:         payload.DefectType,
		InfrastructureType: payload.InfrastructureType,
		GeometryType:       geomType,
	}, nil
}

func parseGeoJSONCoordinates(raw string) [][]float64 {
	if raw == "" {
		return nil
	}
	var g struct {
		Type        string          `json:"type"`
		Coordinates json.RawMessage `json:"coordinates"`
	}
	if err := json.Unmarshal([]byte(raw), &g); err != nil {
		return nil
	}

	switch g.Type {
	case "LineString":
		var pts [][]float64
		if err := json.Unmarshal(g.Coordinates, &pts); err == nil {
			coords := make([][]float64, 0, len(pts))
			for _, pt := range pts {
				if len(pt) >= 2 {
					coords = append(coords, []float64{pt[1], pt[0]}) // перевод [lon, lat] в [lat, lon]
				}
			}
			return coords
		}
	case "MultiLineString":
		var lines [][][]float64
		if err := json.Unmarshal(g.Coordinates, &lines); err == nil {
			coords := make([][]float64, 0)
			for _, line := range lines {
				for _, pt := range line {
					if len(pt) >= 2 {
						coords = append(coords, []float64{pt[1], pt[0]})
					}
				}
			}
			return coords
		}
	}
	return nil
}

func (s *TelemetryService) GetClusters(ctx context.Context) ([]models.TelemetryCluster, error) {
	// Стабильный cluster_id через MIN(id) первой точки кластера
	potholeSQL := `
		WITH points AS (
			SELECT id, user_id, location, bump_force, infrastructure_type, timestamp
			FROM telemetry
			WHERE defect_type = 'pothole'
		),
		clustered AS (
			SELECT
				ST_ClusterDBSCAN(location, $1, 1) OVER () AS c_id,
				id,
				user_id,
				location,
				bump_force,
				infrastructure_type,
				timestamp
			FROM points
		)
		SELECT
			MIN(id) AS cluster_id,
			ST_Y(ST_Centroid(ST_Collect(location))) AS lat,
			ST_X(ST_Centroid(ST_Collect(location))) AS lon,
			MAX(bump_force) AS max_force,
			COUNT(DISTINCT user_id)::int AS unique_users,
			COUNT(*)::int AS total_hits,
			'pothole' AS defect_type,
			MAX(infrastructure_type) AS infrastructure_type,
			COALESCE(MAX(timestamp), NOW()) AS created_at
		FROM clustered
		WHERE c_id IS NOT NULL
		GROUP BY c_id;
	`

	roughSQL := `
		WITH points AS (
			SELECT id, user_id, location, bump_force, infrastructure_type, timestamp
			FROM telemetry
			WHERE defect_type = 'rough_road'
		),
		clustered AS (
			SELECT
				ST_ClusterDBSCAN(location, $1, 1) OVER () AS c_id,
				id,
				user_id,
				location,
				bump_force,
				infrastructure_type,
				timestamp
			FROM points
		)
		SELECT
			(MIN(id) + 100000000)::bigint AS cluster_id,
			ST_Y(ST_Centroid(ST_Collect(location))) AS lat,
			ST_X(ST_Centroid(ST_Collect(location))) AS lon,
			MAX(bump_force) AS max_force,
			COUNT(DISTINCT user_id)::int AS unique_users,
			COUNT(*)::int AS total_hits,
			'rough_road' AS defect_type,
			MAX(infrastructure_type) AS infrastructure_type,
			COALESCE(MAX(timestamp), NOW()) AS created_at,
			COALESCE(ST_AsGeoJSON(ST_Collect(location)), '') AS geojson
		FROM clustered
		WHERE c_id IS NOT NULL
		GROUP BY c_id;
	`

	results := make([]models.TelemetryCluster, 0)

	// 1. Чтение кластеров ям (pothole)
	rows, err := s.pool.Query(ctx, potholeSQL, ClusterEpsDeg)
	if err != nil {
		return nil, fmt.Errorf("ошибка запроса pothole: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var item models.TelemetryCluster
		if err := rows.Scan(
			&item.ClusterID,
			&item.Lat,
			&item.Lon,
			&item.MaxForce,
			&item.UniqueUsers,
			&item.TotalHits,
			&item.DefectType,
			&item.InfrastructureType,
			&item.CreatedAt,
		); err != nil {
			return nil, err
		}
		item.IsConfirmed = (item.UniqueUsers >= 2 || item.TotalHits >= 3)
		results = append(results, item)
	}

	// 2. Чтение кластеризованных участков rough_road со стабильным ID
	roughRows, err := s.pool.Query(ctx, roughSQL, ClusterEpsDeg)
	if err != nil {
		return nil, fmt.Errorf("ошибка запроса rough_road: %w", err)
	}
	defer roughRows.Close()

	for roughRows.Next() {
		var item models.TelemetryCluster
		var geojsonStr string
		if err := roughRows.Scan(
			&item.ClusterID,
			&item.Lat,
			&item.Lon,
			&item.MaxForce,
			&item.UniqueUsers,
			&item.TotalHits,
			&item.DefectType,
			&item.InfrastructureType,
			&item.CreatedAt,
			&geojsonStr,
		); err != nil {
			return nil, err
		}
		item.IsConfirmed = (item.UniqueUsers >= 2 || item.TotalHits >= 3)
		item.Coordinates = parseGeoJSONCoordinates(geojsonStr)
		results = append(results, item)
	}

	return results, nil
}

func (s *TelemetryService) RecordDistance(ctx context.Context, userID string, meters float64) (*models.DistanceResponse, error) {
	if meters <= 0 {
		return &models.DistanceResponse{
			Status:      "ok",
			AddedMeters: 0,
		}, nil
	}

	var total float64
	if userID != "" && userID != "anonymous" {
		query := `
			UPDATE users
			SET total_distance_meters = COALESCE(total_distance_meters, 0) + $1
			WHERE id = $2
			RETURNING total_distance_meters;
		`
		err := s.pool.QueryRow(ctx, query, meters, userID).Scan(&total)
		if err != nil {
			return nil, fmt.Errorf("ошибка обновления пробега пользователя: %w", err)
		}
	}

	return &models.DistanceResponse{
		Status:              "ok",
		AddedMeters:         meters,
		TotalDistanceMeters: total,
	}, nil
}

// AddComment сохраняет комментарий к стабильному ID дефекта
func (s *TelemetryService) AddComment(ctx context.Context, clusterID int64, userID, authorName, text string) (*models.DefectComment, error) {
	cleanText := strings.TrimSpace(text)
	if cleanText == "" {
		return nil, fmt.Errorf("текст комментария не может быть пустым")
	}

	// Защита: если имя автора не передано, извлекаем реальное имя пользователя из таблицы users
	if authorName == "" {
		var realName string
		_ = s.pool.QueryRow(ctx, `SELECT name FROM users WHERE id = $1;`, userID).Scan(&realName)
		if strings.TrimSpace(realName) != "" {
			authorName = strings.TrimSpace(realName)
		} else {
			authorName = "Водитель"
		}
	}

	query := `
		INSERT INTO defect_comments (cluster_id, user_id, author_name, text, created_at)
		VALUES ($1, $2, $3, $4, NOW())
		RETURNING id, cluster_id, user_id, author_name, text, created_at;
	`
	var c models.DefectComment
	err := s.pool.QueryRow(ctx, query, clusterID, userID, authorName, cleanText).Scan(
		&c.ID, &c.ClusterID, &c.UserID, &c.AuthorName, &c.Text, &c.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("ошибка добавления комментария: %w", err)
	}
	return &c, nil
}

// GetComments возвращает список комментариев к дефекту
func (s *TelemetryService) GetComments(ctx context.Context, clusterID int64) ([]models.DefectComment, error) {
	query := `
		SELECT id, cluster_id, user_id, author_name, text, created_at
		FROM defect_comments
		WHERE cluster_id = $1
		ORDER BY created_at DESC;
	`
	rows, err := s.pool.Query(ctx, query, clusterID)
	if err != nil {
		return nil, fmt.Errorf("ошибка получения комментариев: %w", err)
	}
	defer rows.Close()

	comments := make([]models.DefectComment, 0)
	for rows.Next() {
		var c models.DefectComment
		if err := rows.Scan(&c.ID, &c.ClusterID, &c.UserID, &c.AuthorName, &c.Text, &c.CreatedAt); err != nil {
			return nil, err
		}
		comments = append(comments, c)
	}
	return comments, nil
}
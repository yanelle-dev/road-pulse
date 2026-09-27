package service

import (
	"context"
	"fmt"
	"math"
	"strings"

	"easyride_backend_go/internal/models"
	"easyride_backend_go/internal/osrm"

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

func (s *TelemetryService) GetClusters(ctx context.Context) ([]models.TelemetryCluster, error) {
	potholeSQL := `
		WITH points AS (
			SELECT user_id, location, bump_force, infrastructure_type
			FROM telemetry
			WHERE defect_type = 'pothole'
		),
		clustered AS (
			SELECT
				ST_ClusterDBSCAN(location, $1, 1) OVER () AS cluster_id,
				user_id,
				location,
				bump_force,
				infrastructure_type
			FROM points
		)
		SELECT
			cluster_id,
			ST_Y(ST_Centroid(ST_Collect(location))) AS lat,
			ST_X(ST_Centroid(ST_Collect(location))) AS lon,
			MAX(bump_force) AS max_force,
			COUNT(DISTINCT user_id)::int AS unique_users,
			COUNT(*)::int AS total_hits,
			'pothole' AS defect_type,
			MAX(infrastructure_type) AS infrastructure_type
		FROM clustered
		WHERE cluster_id IS NOT NULL
		GROUP BY cluster_id;
	`

	roughSQL := `
		SELECT
			id AS cluster_id,
			ST_Y(ST_Centroid(location)) AS lat,
			ST_X(ST_Centroid(location)) AS lon,
			bump_force AS max_force,
			1 AS unique_users,
			1 AS total_hits,
			defect_type,
			infrastructure_type
		FROM telemetry
		WHERE defect_type = 'rough_road';
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
		); err != nil {
			return nil, err
		}
		item.IsConfirmed = (item.UniqueUsers >= 2 || item.TotalHits >= 3)
		results = append(results, item)
	}

	// 2. Чтение участков rough_road
	roughRows, err := s.pool.Query(ctx, roughSQL)
	if err != nil {
		return nil, fmt.Errorf("ошибка запроса rough_road: %w", err)
	}
	defer roughRows.Close()

	const offset = 1000000
	for roughRows.Next() {
		var item models.TelemetryCluster
		if err := roughRows.Scan(
			&item.ClusterID,
			&item.Lat,
			&item.Lon,
			&item.MaxForce,
			&item.UniqueUsers,
			&item.TotalHits,
			&item.DefectType,
			&item.InfrastructureType,
		); err != nil {
			return nil, err
		}
		item.ClusterID += offset
		item.IsConfirmed = false
		results = append(results, item)
	}

	return results, nil
}
package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"road_pulse/backend/internal/models"
	"road_pulse/backend/internal/osrm"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	MinSpeedKMH  = 20.0
	BaseSpeedKMH = 20.0

	// ClusterEpsMeters — радиус DBSCAN в метрах (в проекции 3857 с поправкой на широту).
	// minpoints = 1 даёт цепочки: при 20 м соседние ямы вдоль плохой дороги сливались в один «дефект»,
	// поэтому радиус не больше типичной погрешности привязанной к дороге точки.
	ClusterEpsMeters = 12.0
	// ClusterMaxAgeDays — старые данные не участвуют в кластерах (ямы ремонтируют).
	ClusterMaxAgeDays = 180
	// RoughClusterIDOffset — смещение cluster_id для rough_road.
	RoughClusterIDOffset int64 = 100000000

	MaxSpeedKMH            = 300.0
	MaxBumpForce           = 200.0
	MaxTrajectoryPoints    = 50
	MaxDistanceBatchMeters = 5000.0
	MaxCommentRunes        = 1000
	MaxClientEventIDLen    = 64
	MaxAccuracyM           = 1000.0
	MaxRoadNameRunes       = 120

	// Шкала серьёзности дублирует клиент (app/lib/constants.dart, detection.dart):
	// сила удара сравнивается с порогом обнаружения для этой скорости, поэтому оценка не зависит от скорости.
	BumpBaseThresholdMs2 = 7.0
	BumpSpeedFactor      = 0.12
	RoughRmsThresholdMs2 = 1.5
	RoughForceScale      = 5.0 // bump_force участка тряски = среднее RMS × RoughForceScale
	SeverityMediumRatio  = 2.0
	SeverityHardRatio    = 3.5

	// Повторный проезд той же ямы тем же пользователем в этом окне не создаёт новую запись:
	// иначе рейтинг и «подтверждения» можно накрутить, ездя туда-обратно.
	DedupRadiusMeters  = 15.0
	DedupWindowMinutes = 120

	// ClusterCacheTTL — GET /telemetry отдаёт кэш: полный DBSCAN по таблице на каждый запрос дорог.
	ClusterCacheTTL = 15 * time.Second
	// EventTimeMaxAge / EventTimeMaxFuture — допустимое окно для времени события с устройства.
	EventTimeMaxAge    = 48 * time.Hour
	EventTimeMaxFuture = 5 * time.Minute
)

var (
	ErrInvalidTelemetry = errors.New("invalid telemetry payload")
	ErrInvalidDistance  = errors.New("invalid distance")
	ErrInvalidComment   = errors.New("invalid comment")
)

type clusterCache struct {
	mu   sync.Mutex
	at   time.Time
	data []models.TelemetryCluster
}

type TelemetryService struct {
	pool  *pgxpool.Pool
	osrm  *osrm.Client
	cache clusterCache
}

func NewTelemetryService(pool *pgxpool.Pool, osrmClient *osrm.Client) *TelemetryService {
	return &TelemetryService{
		pool: pool,
		osrm: osrmClient,
	}
}

func finite(f float64) bool { return !math.IsNaN(f) && !math.IsInf(f, 0) }

func validCoord(lat, lon float64) bool {
	return finite(lat) && finite(lon) && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180
}

// ValidatePayload проверяет вход телеметрии. Хендлер должен отдавать 400 при errors.Is(err, ErrInvalidTelemetry).
func ValidatePayload(p *models.TelemetryPayload) error {
	if !validCoord(p.Latitude, p.Longitude) {
		return fmt.Errorf("%w: coordinates", ErrInvalidTelemetry)
	}
	if !finite(p.SpeedKMH) || p.SpeedKMH < 0 || p.SpeedKMH > MaxSpeedKMH {
		return fmt.Errorf("%w: speed", ErrInvalidTelemetry)
	}
	if !finite(p.BumpForce) || p.BumpForce <= 0 || p.BumpForce > MaxBumpForce {
		return fmt.Errorf("%w: bump_force", ErrInvalidTelemetry)
	}
	if p.DefectType != "pothole" && p.DefectType != "rough_road" {
		return fmt.Errorf("%w: defect_type", ErrInvalidTelemetry)
	}
	if len(p.ClientEventID) > MaxClientEventIDLen {
		return fmt.Errorf("%w: client_event_id", ErrInvalidTelemetry)
	}
	if len(p.InfrastructureType) > 32 {
		return fmt.Errorf("%w: infrastructure_type", ErrInvalidTelemetry)
	}
	if p.HeadingDeg != nil && (!finite(*p.HeadingDeg) || *p.HeadingDeg < 0 || *p.HeadingDeg >= 360) {
		return fmt.Errorf("%w: heading_deg", ErrInvalidTelemetry)
	}
	if !finite(p.AccuracyM) || p.AccuracyM < 0 || p.AccuracyM > MaxAccuracyM {
		return fmt.Errorf("%w: accuracy_m", ErrInvalidTelemetry)
	}
	if len(p.Trajectory) > MaxTrajectoryPoints {
		return fmt.Errorf("%w: trajectory too long", ErrInvalidTelemetry)
	}
	for _, pt := range p.Trajectory {
		if !validCoord(pt.Lat, pt.Lon) {
			return fmt.Errorf("%w: trajectory point", ErrInvalidTelemetry)
		}
	}
	return nil
}

// resolveEventTime возвращает время события с устройства, если оно правдоподобно;
// иначе nil, и БД подставит NOW() (часы на телефоне могут врать).
func resolveEventTime(ms int64) *time.Time {
	if ms <= 0 {
		return nil
	}
	t := time.UnixMilli(ms)
	now := time.Now()
	if t.After(now.Add(EventTimeMaxFuture)) || t.Before(now.Add(-EventTimeMaxAge)) {
		return nil
	}
	return &t
}

func (s *TelemetryService) CalculateNormalizedForce(bumpForce, speedKMH float64) float64 {
	safeSpeed := math.Max(speedKMH, BaseSpeedKMH)
	return bumpForce * (BaseSpeedKMH / safeSpeed)
}

// SeverityFor: 1 — ровно, 2 — заметно, 3 — жёстко. Нормализованная по скорости сила для этого не годится:
// порог обнаружения растёт со скоростью, и у порога она почти одинакова на любой скорости.
func SeverityFor(defectType string, rawForce, speedKMH float64) int {
	threshold := math.Max(BumpBaseThresholdMs2, BumpSpeedFactor*speedKMH)
	if defectType == "rough_road" {
		threshold = RoughRmsThresholdMs2 * RoughForceScale
	}
	ratio := rawForce / threshold
	switch {
	case ratio > SeverityHardRatio:
		return 3
	case ratio > SeverityMediumRatio:
		return 2
	default:
		return 1
	}
}

func truncateRunes(s string, limit int) string {
	s = strings.TrimSpace(s)
	if utf8.RuneCountInString(s) <= limit {
		return s
	}
	return string([]rune(s)[:limit])
}

// ResolveLocation привязывает событие к дороге и возвращает WKT, тип геометрии и название дороги:
//   - rough_road с треком > 2 точек -> /match (LINESTRING);
//   - всё остальное (pothole и фолбэк) -> /nearest от координат события с учётом курса (POINT).
//
// Для ям трек не используется: клиент присылает точку удара, а первая точка трека была самой старой.
func (s *TelemetryService) ResolveLocation(ctx context.Context, p *models.TelemetryPayload) (wkt, geomType, roadName string) {
	if p.DefectType == "rough_road" && len(p.Trajectory) > 2 {
		if w, g, name, ok := s.osrm.Match(ctx, p.Trajectory); ok {
			return w, g, truncateRunes(name, MaxRoadNameRunes)
		}
	}

	snap := s.osrm.Nearest(ctx, p.Latitude, p.Longitude, p.HeadingDeg)
	return fmt.Sprintf("POINT(%f %f)", snap.Lon, snap.Lat), "Point", truncateRunes(snap.Name, MaxRoadNameRunes)
}

// findRecentDuplicate ищет запись того же пользователя и типа рядом с новой геометрией за последние часы.
// Для гостей проверки нет: их события нельзя отнести к одному человеку.
func (s *TelemetryService) findRecentDuplicate(ctx context.Context, userID, defectType, wkt string) (*models.TelemetryResponse, error) {
	if userID == "" || userID == "anonymous" {
		return nil, nil
	}

	query := `
		SELECT id, ST_Y(ST_Centroid(location)), ST_X(ST_Centroid(location)),
			bump_force, COALESCE(severity, 1)::int, COALESCE(road_name, '')
		FROM telemetry
		WHERE user_id = $1
		  AND defect_type = $2
		  AND timestamp > NOW() - make_interval(mins => $3::int)
		  AND ST_DWithin(location::geography, ST_GeomFromText($4, 4326)::geography, $5::float8)
		ORDER BY timestamp DESC
		LIMIT 1;
	`
	var r models.TelemetryResponse
	err := s.pool.QueryRow(ctx, query, userID, defectType, DedupWindowMinutes, wkt, DedupRadiusMeters).Scan(
		&r.ID, &r.SnappedLat, &r.SnappedLon, &r.BumpForce, &r.Severity, &r.RoadName,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("ошибка поиска дубля: %w", err)
	}
	return &r, nil
}

func (s *TelemetryService) SaveTelemetry(ctx context.Context, payload *models.TelemetryPayload) (*models.TelemetryResponse, error) {
	if payload.DefectType == "" {
		payload.DefectType = "pothole"
	}
	if payload.InfrastructureType == "" {
		payload.InfrastructureType = "road"
	}
	if err := ValidatePayload(payload); err != nil {
		return nil, err
	}

	locationWKT, geomType, roadName := s.ResolveLocation(ctx, payload)

	dup, err := s.findRecentDuplicate(ctx, payload.UserID, payload.DefectType, locationWKT)
	if err != nil {
		return nil, err
	}
	if dup != nil {
		dup.Status = "ok"
		dup.Duplicate = true
		dup.DefectType = payload.DefectType
		dup.InfrastructureType = payload.InfrastructureType
		dup.GeometryType = geomType
		return dup, nil
	}

	normalizedForce := s.CalculateNormalizedForce(payload.BumpForce, payload.SpeedKMH)
	severity := SeverityFor(payload.DefectType, payload.BumpForce, payload.SpeedKMH)

	// Идемпотентность по (user_id, client_event_id): чужой client_event_id не затрагивает чужие строки.
	// xmax <> 0 у строки, обновлённой веткой ON CONFLICT, то есть это повтор.
	query := `
		INSERT INTO telemetry (
			user_id, location, speed_kmh, bump_force, defect_type, infrastructure_type,
			timestamp, client_event_id, raw_bump_force, severity, road_name
		) VALUES (
			$1, ST_GeomFromText($2, 4326), $3, $4, $5, $6,
			COALESCE($7::timestamptz, NOW()), $8, $9, $10, NULLIF($11::text, '')
		)
		ON CONFLICT (user_id, client_event_id) DO UPDATE SET client_event_id = EXCLUDED.client_event_id
		RETURNING id, ST_Y(ST_Centroid(location)), ST_X(ST_Centroid(location)),
			bump_force, COALESCE(severity, 1)::int, COALESCE(road_name, ''), (xmax::text::bigint <> 0);
	`

	var clientID *string
	if payload.ClientEventID != "" {
		clientID = &payload.ClientEventID
	}

	resp := &models.TelemetryResponse{
		Status:             "ok",
		DefectType:         payload.DefectType,
		InfrastructureType: payload.InfrastructureType,
		GeometryType:       geomType,
	}
	err = s.pool.QueryRow(ctx, query,
		payload.UserID,
		locationWKT,
		payload.SpeedKMH,
		normalizedForce,
		payload.DefectType,
		payload.InfrastructureType,
		resolveEventTime(payload.EventTimeMs),
		clientID,
		payload.BumpForce,
		severity,
		roadName,
	).Scan(&resp.ID, &resp.SnappedLat, &resp.SnappedLon, &resp.BumpForce, &resp.Severity, &resp.RoadName, &resp.Duplicate)
	if err != nil {
		return nil, fmt.Errorf("ошибка вставки в БД: %w", err)
	}
	return resp, nil
}

func swapLonLat(pts [][]float64) [][]float64 {
	coords := make([][]float64, 0, len(pts))
	for _, pt := range pts {
		if len(pt) >= 2 {
			coords = append(coords, []float64{pt[1], pt[0]}) // [lon, lat] -> [lat, lon]
		}
	}
	return coords
}

// parseGeoJSONLines разбирает линии GeoJSON по отдельности: склеенные в одну ломаную линии
// давали на карте прямые «перемычки» между концом одной и началом другой.
func parseGeoJSONLines(raw string) [][][]float64 {
	if raw == "" {
		return nil
	}
	var g struct {
		Type        string            `json:"type"`
		Coordinates json.RawMessage   `json:"coordinates"`
		Geometries  []json.RawMessage `json:"geometries"`
	}
	if err := json.Unmarshal([]byte(raw), &g); err != nil {
		return nil
	}

	switch g.Type {
	case "LineString":
		var pts [][]float64
		if err := json.Unmarshal(g.Coordinates, &pts); err == nil {
			return [][][]float64{swapLonLat(pts)}
		}
	case "MultiLineString":
		var lines [][][]float64
		if err := json.Unmarshal(g.Coordinates, &lines); err == nil {
			out := make([][][]float64, 0, len(lines))
			for _, line := range lines {
				out = append(out, swapLonLat(line))
			}
			return out
		}
	case "GeometryCollection":
		out := make([][][]float64, 0)
		for _, sub := range g.Geometries {
			out = append(out, parseGeoJSONLines(string(sub))...)
		}
		return out
	}
	return nil
}

// parseGeoJSONCoordinates отдаёт все точки одним списком [lat, lon] (формат для старых клиентов).
func parseGeoJSONCoordinates(raw string) [][]float64 {
	if raw == "" {
		return nil
	}
	var g struct {
		Type        string            `json:"type"`
		Coordinates json.RawMessage   `json:"coordinates"`
		Geometries  []json.RawMessage `json:"geometries"`
	}
	if err := json.Unmarshal([]byte(raw), &g); err != nil {
		return nil
	}

	switch g.Type {
	case "Point":
		var pt []float64
		if err := json.Unmarshal(g.Coordinates, &pt); err == nil {
			return swapLonLat([][]float64{pt})
		}
	case "LineString", "MultiPoint":
		var pts [][]float64
		if err := json.Unmarshal(g.Coordinates, &pts); err == nil {
			return swapLonLat(pts)
		}
	case "MultiLineString":
		var lines [][][]float64
		if err := json.Unmarshal(g.Coordinates, &lines); err == nil {
			coords := make([][]float64, 0)
			for _, line := range lines {
				coords = append(coords, swapLonLat(line)...)
			}
			return coords
		}
	case "GeometryCollection":
		coords := make([][]float64, 0)
		for _, sub := range g.Geometries {
			coords = append(coords, parseGeoJSONCoordinates(string(sub))...)
		}
		return coords
	}
	return nil
}

// clusterSQL — общий запрос кластеров.
//
//	$1 eps в метрах, $2 defect_type, $3 возраст в днях, $4 смещение cluster_id.
//
// Кластеризация идёт в EPSG:3857 (метры), eps делится на cos(широты), потому что
// Web Mercator растягивает расстояния в 1/cos(lat) раз. minpoints = 1 оставлен
// намеренно: одиночные удары должны остаться неподтверждёнными маркерами.
// Записи 'anonymous' не считаются «водителями»: это гости и удалённые аккаунты, а не отдельные люди.
const clusterSQL = `
	WITH points AS (
		SELECT id, user_id, location, bump_force, COALESCE(severity, 1) AS severity,
			COALESCE(road_name, '') AS road_name, infrastructure_type, timestamp
		FROM telemetry
		WHERE defect_type = $2::text
		  AND timestamp > NOW() - make_interval(days => $3::int)
	),
	ref AS (
		SELECT COALESCE(AVG(ST_Y(ST_Centroid(location))), 0) AS lat0 FROM points
	),
	clustered AS (
		SELECT
			ST_ClusterDBSCAN(
				ST_Transform(p.location, 3857),
				$1::float8 / GREATEST(cos(radians(r.lat0)), 0.2),
				1
			) OVER () AS c_id,
			p.id, p.user_id, p.location, p.bump_force, p.severity, p.road_name, p.infrastructure_type, p.timestamp
		FROM points p CROSS JOIN ref r
	)
	SELECT
		(MIN(id) + $4::bigint)::bigint AS cluster_id,
		ST_Y(ST_Centroid(ST_Collect(location))) AS lat,
		ST_X(ST_Centroid(ST_Collect(location))) AS lon,
		(CASE WHEN COUNT(*) >= 3
			THEN percentile_cont(0.75) WITHIN GROUP (ORDER BY bump_force)
			ELSE MAX(bump_force)
		END)::float8 AS max_force,
		(CASE WHEN COUNT(*) >= 3
			THEN percentile_disc(0.75) WITHIN GROUP (ORDER BY severity)
			ELSE MAX(severity)
		END)::int AS severity,
		(COUNT(DISTINCT user_id) FILTER (WHERE user_id <> 'anonymous'))::int AS unique_users,
		COUNT(*)::int AS total_hits,
		(COUNT(DISTINCT (user_id, timestamp::date)) FILTER (WHERE user_id <> 'anonymous'))::int AS user_days,
		$2::text AS defect_type,
		MAX(infrastructure_type) AS infrastructure_type,
		COALESCE(MODE() WITHIN GROUP (ORDER BY road_name) FILTER (WHERE road_name <> ''), '') AS road_name,
		COALESCE(MAX(timestamp), NOW()) AS created_at,
		COALESCE(ST_AsGeoJSON(ST_Collect(location) FILTER (
			WHERE ST_GeometryType(location) IN ('ST_LineString', 'ST_MultiLineString')
		)), '') AS geojson
	FROM clustered
	WHERE c_id IS NOT NULL
	GROUP BY c_id;
`

func (s *TelemetryService) queryClusters(ctx context.Context, defectType string, idOffset int64) ([]models.TelemetryCluster, error) {
	rows, err := s.pool.Query(ctx, clusterSQL, ClusterEpsMeters, defectType, ClusterMaxAgeDays, idOffset)
	if err != nil {
		return nil, fmt.Errorf("ошибка запроса %s: %w", defectType, err)
	}
	defer rows.Close()

	out := make([]models.TelemetryCluster, 0)
	for rows.Next() {
		var item models.TelemetryCluster
		var userDays int
		var geojson string
		if err := rows.Scan(
			&item.ClusterID,
			&item.Lat,
			&item.Lon,
			&item.MaxForce,
			&item.Severity,
			&item.UniqueUsers,
			&item.TotalHits,
			&userDays,
			&item.DefectType,
			&item.InfrastructureType,
			&item.RoadName,
			&item.CreatedAt,
			&geojson,
		); err != nil {
			return nil, err
		}
		// Подтверждение: 2+ разных пользователя ИЛИ 3+ разных «пользователь-день».
		// Три удара одного человека за одну поездку больше не подтверждают дефект.
		item.IsConfirmed = item.UniqueUsers >= 2 || userDays >= 3
		if defectType == "rough_road" {
			item.Lines = parseGeoJSONLines(geojson)
			item.Coordinates = parseGeoJSONCoordinates(geojson)
		}
		out = append(out, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("ошибка чтения %s: %w", defectType, err)
	}
	return out, nil
}

// GetClusters отдаёт кэш на ClusterCacheTTL; мьютекс заодно сворачивает параллельные пересчёты.
// При ошибке БД возвращается устаревший кэш, если он есть.
func (s *TelemetryService) GetClusters(ctx context.Context) ([]models.TelemetryCluster, error) {
	s.cache.mu.Lock()
	defer s.cache.mu.Unlock()

	if s.cache.data != nil && time.Since(s.cache.at) < ClusterCacheTTL {
		return s.cache.data, nil
	}

	potholes, err := s.queryClusters(ctx, "pothole", 0)
	if err == nil {
		var rough []models.TelemetryCluster
		rough, err = s.queryClusters(ctx, "rough_road", RoughClusterIDOffset)
		if err == nil {
			s.cache.data = append(potholes, rough...)
			s.cache.at = time.Now()
			return s.cache.data, nil
		}
	}
	if s.cache.data != nil {
		return s.cache.data, nil
	}
	return nil, err
}

func (s *TelemetryService) RecordDistance(ctx context.Context, userID string, meters float64) (*models.DistanceResponse, error) {
	if !finite(meters) || meters > MaxDistanceBatchMeters {
		return nil, ErrInvalidDistance
	}
	if meters <= 0 {
		return &models.DistanceResponse{Status: "ok", AddedMeters: 0}, nil
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
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrUserNotFound
		}
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

// AddComment сохраняет комментарий. Имя автора берётся из users, а не из тела запроса
// (иначе можно подписаться чужим именем); параметр authorName оставлен для совместимости.
func (s *TelemetryService) AddComment(ctx context.Context, clusterID int64, userID, authorName, text string) (*models.DefectComment, error) {
	cleanText := strings.TrimSpace(text)
	if cleanText == "" || utf8.RuneCountInString(cleanText) > MaxCommentRunes {
		return nil, ErrInvalidComment
	}
	_ = authorName

	var realName string
	_ = s.pool.QueryRow(ctx, `SELECT name FROM users WHERE id = $1;`, userID).Scan(&realName)
	name := strings.TrimSpace(realName)
	if name == "" {
		name = "Водитель"
	}

	query := `
		INSERT INTO defect_comments (cluster_id, user_id, author_name, text, created_at)
		VALUES ($1, $2, $3, $4, NOW())
		RETURNING id, cluster_id, user_id, author_name, text, created_at;
	`
	var c models.DefectComment
	err := s.pool.QueryRow(ctx, query, clusterID, userID, name, cleanText).Scan(
		&c.ID, &c.ClusterID, &c.UserID, &c.AuthorName, &c.Text, &c.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("ошибка добавления комментария: %w", err)
	}
	return &c, nil
}

// GetComments возвращает комментарии к дефекту (новые сверху, как и раньше).
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
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return comments, nil
}
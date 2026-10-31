package models

import "time"

type TrajectoryPoint struct {
	Lat       float64 `json:"lat"`
	Lon       float64 `json:"lon"`
	Timestamp float64 `json:"timestamp"`
}

type TelemetryPayload struct {
	UserID             string            `json:"user_id"`
	Latitude           float64           `json:"latitude"`
	Longitude          float64           `json:"longitude"`
	SpeedKMH           float64           `json:"speed_kmh"`
	BumpForce          float64           `json:"bump_force"`
	DefectType         string            `json:"defect_type"`         // "pothole" | "rough_road"
	InfrastructureType string            `json:"infrastructure_type"` // "road" | "bridge" | "tunnel"
	Trajectory         []TrajectoryPoint `json:"trajectory"`
	EventTimeMs        int64             `json:"event_time_ms,omitempty"`   // время удара на устройстве (мс, Unix)
	ClientEventID      string            `json:"client_event_id,omitempty"` // для идемпотентных повторов
	HeadingDeg         *float64          `json:"heading_deg,omitempty"`     // курс движения: выбирает нужный сегмент дороги
	AccuracyM          float64           `json:"accuracy_m,omitempty"`      // погрешность GPS-фикса
}

type TelemetryResponse struct {
	Status             string  `json:"status"`
	ID                 int64   `json:"id"`
	SnappedLat         float64 `json:"snapped_lat"`
	SnappedLon         float64 `json:"snapped_lon"`
	BumpForce          float64 `json:"bump_force"`
	Severity           int     `json:"severity"`
	RoadName           string  `json:"road_name,omitempty"`
	DefectType         string  `json:"defect_type"`
	InfrastructureType string  `json:"infrastructure_type"`
	GeometryType       string  `json:"geometry_type"`
	Duplicate          bool    `json:"duplicate"` // повтор события или та же яма от того же пользователя: клиент её не засчитывает
}

type TelemetryCluster struct {
	ClusterID          int64         `json:"cluster_id"`
	Lat                float64       `json:"lat"`
	Lon                float64       `json:"lon"`
	MaxForce           float64       `json:"max_force"`
	Severity           int           `json:"severity"` // 1 — ровно, 2 — заметно, 3 — жёстко
	UniqueUsers        int           `json:"unique_users"`
	TotalHits          int           `json:"total_hits"`
	IsConfirmed        bool          `json:"is_confirmed"`
	DefectType         string        `json:"defect_type"`
	InfrastructureType string        `json:"infrastructure_type"`
	RoadName           string        `json:"road_name,omitempty"`
	CreatedAt          time.Time     `json:"created_at"`
	Coordinates        [][]float64   `json:"coordinates,omitempty"` // [[lat, lon], ...] одной ломаной, для старых клиентов
	Lines              [][][]float64 `json:"lines,omitempty"`       // отдельные линии rough_road: [[[lat, lon], ...], ...]
}

type DistancePayload struct {
	DistanceMeters float64 `json:"distance_meters"`
}

type DistanceResponse struct {
	Status              string  `json:"status"`
	AddedMeters         float64 `json:"added_meters"`
	TotalDistanceMeters float64 `json:"total_distance_meters"`
}

type DefectComment struct {
	ID         int64     `json:"id"`
	ClusterID  int64     `json:"cluster_id"`
	UserID     string    `json:"user_id"`
	AuthorName string    `json:"author_name"`
	Text       string    `json:"text"`
	CreatedAt  time.Time `json:"created_at"`
}

type CreateCommentPayload struct {
	ClusterID  int64  `json:"cluster_id"`
	Text       string `json:"text"`
	AuthorName string `json:"author_name,omitempty"`
}
package models

import "time"

type Trip struct {
	ID             int64      `json:"id"`
	UserID         string     `json:"user_id"`
	StartedAt      time.Time  `json:"started_at"`
	EndedAt        *time.Time `json:"ended_at"`
	DistanceMeters float64    `json:"distance_meters"`
	DefectsCount   int        `json:"defects_count"`
	SmoothRatio    float64    `json:"smooth_ratio"`
	MediumRatio    float64    `json:"medium_ratio"`
	HardRatio      float64    `json:"hard_ratio"`
	CreatedAt      time.Time  `json:"created_at"`
}

type StartTripResponse struct {
	TripID int64 `json:"trip_id"`
}

type FinishTripPayload struct {
	TripID         int64   `json:"trip_id"`
	DistanceMeters float64 `json:"distance_meters"`
	DefectsCount   int     `json:"defects_count"`
	SmoothRatio    float64 `json:"smooth_ratio"`
	MediumRatio    float64 `json:"medium_ratio"`
	HardRatio      float64 `json:"hard_ratio"`
}
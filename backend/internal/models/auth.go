package models

import "time"

type RequestCodePayload struct {
	Phone string `json:"phone"`
}


type RequestCodeResponse struct {
	Status     string `json:"status"`
	RetryAfter int    `json:"retry_after"`
	Code       string `json:"code,omitempty"`
}

type VerifyCodePayload struct {
	Phone string `json:"phone"`
	Code  string `json:"code"`
}

type RefreshTokenPayload struct {
	RefreshToken string `json:"refresh_token"`
}

type UserProfile struct {
	ID                   string        `json:"id"`
	Phone                string        `json:"phone"`
	Name                 string        `json:"name"`
	City                 string        `json:"city"`
	CarClearance         int           `json:"car_clearance"`
	TotalDistanceMeters  float64       `json:"total_distance_meters"`
	TotalDefects         int           `json:"total_defects"`
	PotholeCount         int           `json:"pothole_count"`
	RoughRoadCount       int           `json:"rough_road_count"`
	Rating               int           `json:"rating"`
	SavedSuspensions     int           `json:"saved_suspensions"`
	CommunityPercentile  int           `json:"community_percentile"`
	StreakDays           int           `json:"streak_days"`
	UnlockedAchievements int           `json:"unlocked_achievements"`
	ActivityDays         []ActivityDay `json:"activity_days"`
	CreatedAt            time.Time     `json:"created_at"`
}


type ActivityDay struct {
	Date           string  `json:"date"`
	DistanceMeters float64 `json:"distance_meters"`
	Defects        int     `json:"defects"`
}

type AuthResponse struct {
	AccessToken  string      `json:"access_token"`
	RefreshToken string      `json:"refresh_token"`
	User         UserProfile `json:"user"`
	IsNewUser    bool        `json:"is_new_user"`
}

type UpdateProfilePayload struct {
	Name         *string `json:"name,omitempty"`
	City         *string `json:"city,omitempty"`
	CarClearance *int    `json:"car_clearance,omitempty"`
}


type SyncStatsPayload struct {
	StreakDays           int `json:"streak_days"`
	UnlockedAchievements int `json:"unlocked_achievements"`
}
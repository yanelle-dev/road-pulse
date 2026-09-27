package models

import "time"

type RequestCodePayload struct {
	Phone string `json:"phone"`
}

type VerifyCodePayload struct {
	Phone string `json:"phone"`
	Code  string `json:"code"`
}

type RefreshTokenPayload struct {
	RefreshToken string `json:"refresh_token"`
}

type UserProfile struct {
	ID           string    `json:"id"`
	Phone        string    `json:"phone"`
	Name         string    `json:"name"`
	City         string    `json:"city"`
	CarClearance int       `json:"car_clearance"`
	CreatedAt    time.Time `json:"created_at"`
}

type AuthResponse struct {
	AccessToken  string      `json:"access_token"`
	RefreshToken string      `json:"refresh_token"`
	User         UserProfile `json:"user"`
}

type UpdateProfilePayload struct {
	Name         *string `json:"name,omitempty"`
	City         *string `json:"city,omitempty"`
	CarClearance *int    `json:"car_clearance,omitempty"`
}
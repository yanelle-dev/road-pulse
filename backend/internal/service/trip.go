package service

import (
	"context"
	"errors"
	"fmt"

	"road_pulse/backend/internal/models"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type TripService struct {
	pool *pgxpool.Pool
}

func NewTripService(pool *pgxpool.Pool) *TripService {
	return &TripService{pool: pool}
}

func (s *TripService) StartTrip(ctx context.Context, userID string) (int64, error) {
	var tripID int64
	query := `INSERT INTO trips (user_id, started_at) VALUES ($1, NOW()) RETURNING id;`
	err := s.pool.QueryRow(ctx, query, userID).Scan(&tripID)
	if err != nil {
		return 0, fmt.Errorf("ошибка старта поездки: %w", err)
	}
	return tripID, nil
}

func (s *TripService) FinishTrip(ctx context.Context, userID string, p *models.FinishTripPayload) (*models.Trip, error) {
	query := `
		UPDATE trips
		SET ended_at = NOW(),
			distance_meters = $1,
			defects_count = $2,
			smooth_ratio = $3,
			medium_ratio = $4,
			hard_ratio = $5
		WHERE id = $6 AND user_id = $7
		RETURNING id, user_id, started_at, ended_at, distance_meters, defects_count, smooth_ratio, medium_ratio, hard_ratio, created_at;
	`
	var t models.Trip
	err := s.pool.QueryRow(ctx, query,
		p.DistanceMeters, p.DefectsCount, p.SmoothRatio, p.MediumRatio, p.HardRatio, p.TripID, userID,
	).Scan(
		&t.ID, &t.UserID, &t.StartedAt, &t.EndedAt, &t.DistanceMeters, &t.DefectsCount, &t.SmoothRatio, &t.MediumRatio, &t.HardRatio, &t.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("ошибка завершения поездки: %w", err)
	}
	return &t, nil
}

func (s *TripService) GetLastTrip(ctx context.Context, userID string) (*models.Trip, error) {
	query := `
		SELECT id, user_id, started_at, ended_at, distance_meters, defects_count, smooth_ratio, medium_ratio, hard_ratio, created_at
		FROM trips
		WHERE user_id = $1 AND ended_at IS NOT NULL
		ORDER BY ended_at DESC
		LIMIT 1;
	`
	var t models.Trip
	err := s.pool.QueryRow(ctx, query, userID).Scan(
		&t.ID, &t.UserID, &t.StartedAt, &t.EndedAt, &t.DistanceMeters, &t.DefectsCount, &t.SmoothRatio, &t.MediumRatio, &t.HardRatio, &t.CreatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, fmt.Errorf("ошибка получения последней поездки: %w", err)
	}
	return &t, nil
}
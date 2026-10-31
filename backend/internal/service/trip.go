package service

import (
	"context"
	"errors"
	"fmt"

	"road_pulse/backend/internal/models"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	MaxTripDistanceMeters = 1_500_000.0
	MaxTripDefects        = 10_000
)

var (
	ErrInvalidTrip  = errors.New("некорректные данные поездки")
	ErrTripNotFound = errors.New("поездка не найдена или уже завершена")
)

type TripService struct {
	pool *pgxpool.Pool
}

func NewTripService(pool *pgxpool.Pool) *TripService {
	return &TripService{pool: pool}
}

// normalizeTrip проверяет границы и приводит доли качества к сумме 1: старые версии клиента
// присылали зажатые значения, дававшие сумму больше единицы.
func normalizeTrip(p *models.FinishTripPayload) error {
	ratios := []*float64{&p.SmoothRatio, &p.MediumRatio, &p.HardRatio}
	sum := 0.0
	for _, r := range ratios {
		if !finite(*r) || *r < 0 || *r > 1 {
			return ErrInvalidTrip
		}
		sum += *r
	}
	if !finite(p.DistanceMeters) || p.DistanceMeters < 0 || p.DistanceMeters > MaxTripDistanceMeters ||
		p.DefectsCount < 0 || p.DefectsCount > MaxTripDefects {
		return ErrInvalidTrip
	}

	if sum == 0 {
		p.SmoothRatio = 1
		return nil
	}
	for _, r := range ratios {
		*r /= sum
	}
	return nil
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

// FinishTrip завершает только собственную незавершённую поездку: повторный вызов не перезаписывает итоги.
func (s *TripService) FinishTrip(ctx context.Context, userID string, p *models.FinishTripPayload) (*models.Trip, error) {
	if err := normalizeTrip(p); err != nil {
		return nil, err
	}

	query := `
		UPDATE trips
		SET ended_at = NOW(),
			distance_meters = $1,
			defects_count = $2,
			smooth_ratio = $3,
			medium_ratio = $4,
			hard_ratio = $5
		WHERE id = $6 AND user_id = $7 AND ended_at IS NULL
		RETURNING id, user_id, started_at, ended_at, distance_meters, defects_count, smooth_ratio, medium_ratio, hard_ratio, created_at;
	`
	var t models.Trip
	err := s.pool.QueryRow(ctx, query,
		p.DistanceMeters, p.DefectsCount, p.SmoothRatio, p.MediumRatio, p.HardRatio, p.TripID, userID,
	).Scan(
		&t.ID, &t.UserID, &t.StartedAt, &t.EndedAt, &t.DistanceMeters, &t.DefectsCount, &t.SmoothRatio, &t.MediumRatio, &t.HardRatio, &t.CreatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrTripNotFound
	}
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
package database

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Connect инициализирует пул соединений с PostgreSQL/PostGIS
func Connect(ctx context.Context, dbURL string) (*pgxpool.Pool, error) {
	poolConfig, err := pgxpool.ParseConfig(dbURL)
	if err != nil {
		return nil, fmt.Errorf("ошибка парсинга DATABASE_URL: %w", err)
	}

	poolConfig.MaxConns = 25
	poolConfig.MinConns = 2
	poolConfig.MaxConnIdleTime = 5 * time.Minute

	pool, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		return nil, fmt.Errorf("не удалось создать пул соединений: %w", err)
	}

	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	if err := pool.Ping(pingCtx); err != nil {
		return nil, fmt.Errorf("база данных недоступна: %w", err)
	}

	return pool, nil
}

// InitSchema применяет расширение PostGIS, создает таблицы telemetry, users, otp_codes, refresh_tokens
func InitSchema(ctx context.Context, pool *pgxpool.Pool) error {
	queries := []string{
		"CREATE EXTENSION IF NOT EXISTS postgis;",
		`CREATE TABLE IF NOT EXISTS telemetry (
			id SERIAL PRIMARY KEY,
			user_id VARCHAR NOT NULL,
			location GEOMETRY(Geometry, 4326) NOT NULL,
			speed_kmh DOUBLE PRECISION NOT NULL,
			bump_force DOUBLE PRECISION NOT NULL,
			defect_type VARCHAR NOT NULL DEFAULT 'pothole',
			infrastructure_type VARCHAR NOT NULL DEFAULT 'road',
			timestamp TIMESTAMPTZ DEFAULT NOW()
		);`,
		"CREATE INDEX IF NOT EXISTS idx_telemetry_user_id ON telemetry(user_id);",
		"CREATE INDEX IF NOT EXISTS idx_telemetry_location ON telemetry USING GIST(location);",
		"ALTER TABLE telemetry ADD COLUMN IF NOT EXISTS defect_type VARCHAR DEFAULT 'pothole';",
		"ALTER TABLE telemetry ADD COLUMN IF NOT EXISTS infrastructure_type VARCHAR DEFAULT 'road';",

		// Таблицы подсистемы авторизации
		`CREATE TABLE IF NOT EXISTS users (
			id VARCHAR(64) PRIMARY KEY,
			phone VARCHAR(32) UNIQUE NOT NULL,
			name VARCHAR(100) NOT NULL DEFAULT '',
			city VARCHAR(100) NOT NULL DEFAULT '',
			car_clearance INT NOT NULL DEFAULT 160,
			created_at TIMESTAMPTZ DEFAULT NOW()
		);`,
		"CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);",

		`CREATE TABLE IF NOT EXISTS otp_codes (
			phone VARCHAR(32) PRIMARY KEY,
			code_hash VARCHAR(64) NOT NULL,
			attempts INT NOT NULL DEFAULT 0,
			expires_at TIMESTAMPTZ NOT NULL,
			created_at TIMESTAMPTZ DEFAULT NOW()
		);`,

		`CREATE TABLE IF NOT EXISTS refresh_tokens (
			token_hash VARCHAR(64) PRIMARY KEY,
			user_id VARCHAR(64) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			expires_at TIMESTAMPTZ NOT NULL,
			revoked BOOLEAN NOT NULL DEFAULT false,
			created_at TIMESTAMPTZ DEFAULT NOW()
		);`,
	}

	for _, query := range queries {
		if _, err := pool.Exec(ctx, query); err != nil {
			return fmt.Errorf("ошибка выполнения миграции (%s): %w", query, err)
		}
	}

	return nil
}
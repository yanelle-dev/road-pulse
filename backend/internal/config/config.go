package config

import (
	"os"
)

type Config struct {
	Port        string
	DatabaseURL string
	OSRMBase    string
}

// Load считывает переменные окружения с fallback-значениями по умолчанию
func Load() *Config {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8000"
	}

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgresql://admin:password123@localhost:5432/road_pulse_db"
	}

	osrmBase := os.Getenv("OSRM_BASE")
	if osrmBase == "" {
		osrmBase = "https://router.project-osrm.org"
	}

	return &Config{
		Port:        port,
		DatabaseURL: dbURL,
		OSRMBase:    osrmBase,
	}
}
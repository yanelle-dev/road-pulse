package config

import (
	"log"
	"os"
	"strings"
)

const defaultSMSGateURL = "https://api.sms-gate.app/3rdparty/v1"

type Config struct {
	AppEnv          string
	Port            string
	DatabaseURL     string
	OSRMBase        string
	JWTSecret       string
	TrustProxy      bool
	SMSGateURL      string
	SMSGateUser     string
	SMSGatePassword string
}

// Load считывает переменные окружения и завершает процесс при отсутствии обязательных параметров
func Load() *Config {
	appEnv := os.Getenv("APP_ENV")
	if appEnv == "" {
		appEnv = "development"
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8000"
	}

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("Критическая ошибка: переменная окружения DATABASE_URL не задана. Создайте .env на основе .env.example.")
	}

	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		log.Fatal("Критическая ошибка: переменная окружения JWT_SECRET не задана. Укажите секретный ключ подписи токенов.")
	}

	// Поддержка обоих вариантов имени переменной OSRM
	osrmBase := os.Getenv("OSRM_BASE")
	if osrmBase == "" {
		osrmBase = os.Getenv("OSRM_BASE_URL")
	}
	if osrmBase == "" {
		osrmBase = "https://router.project-osrm.org"
	}

	gateURL := strings.TrimRight(os.Getenv("SMS_GATE_URL"), "/")
	if gateURL == "" {
		gateURL = defaultSMSGateURL
	}

	return &Config{
		AppEnv:          appEnv,
		Port:            port,
		DatabaseURL:     dbURL,
		OSRMBase:        osrmBase,
		JWTSecret:       jwtSecret,
		TrustProxy:      isTruthy(os.Getenv("TRUST_PROXY")),
		SMSGateURL:      gateURL,
		SMSGateUser:     os.Getenv("SMS_GATE_USER"),
		SMSGatePassword: os.Getenv("SMS_GATE_PASSWORD"),
	}
}

func isTruthy(v string) bool {
	switch strings.ToLower(strings.TrimSpace(v)) {
	case "1", "true", "yes":
		return true
	}
	return false
}
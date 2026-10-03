package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"road_pulse/backend/internal/config"
	"road_pulse/backend/internal/database"
	"road_pulse/backend/internal/handler"
	"road_pulse/backend/internal/osrm"
	"road_pulse/backend/internal/service"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

func main() {
	cfg := config.Load()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	log.Printf("Подключение к PostGIS: %s", cfg.DatabaseURL)
	pool, err := database.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("Критическая ошибка: невозможно подключиться к БД: %v", err)
	}
	defer pool.Close()

	if err := database.InitSchema(ctx, pool); err != nil {
		log.Fatalf("Ошибка применения схемы БД: %v", err)
	}
	log.Println("Схема PostGIS, таблицы телеметрии и авторизации успешно готовы")

	// Сервисы
	osrmClient := osrm.NewClient(cfg.OSRMBase)
	telemetryService := service.NewTelemetryService(pool, osrmClient)
	authService := service.NewAuthService(pool, os.Getenv("JWT_SECRET"))

	// Обработчики
	telemetryHandler := handler.NewTelemetryHandler(telemetryService)
	authHandler := handler.NewAuthHandler(authService)

	r := chi.NewRouter()

	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	// Проверка здоровья
	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		var version string
		if err := pool.QueryRow(r.Context(), "SELECT PostGIS_Version()").Scan(&version); err != nil {
			w.WriteHeader(http.StatusServiceUnavailable)
			_ = json.NewEncoder(w).Encode(map[string]string{"detail": fmt.Sprintf("DB unavailable: %v", err)})
			return
		}
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(map[string]string{"status": "ok", "postgis": version})
	})

	r.Route("/api/v1", func(r chi.Router) {
		// Роуты авторизации
		r.Route("/auth", func(r chi.Router) {
			r.Post("/request-code", authHandler.RequestCode)
			r.Post("/verify-code", authHandler.VerifyCode)
			r.Post("/refresh", authHandler.Refresh)

			// Защищённые роуты профиля (требуют JWT Bearer)
			r.Group(func(r chi.Router) {
				r.Use(handler.RequireAuth(authService))
				r.Get("/me", authHandler.GetMe)
				r.Patch("/me", authHandler.UpdateMe)
			})
		})

		// Телеметрия: использует токен, если он передан, либо fallback для обратной совместимости
		r.Group(func(r chi.Router) {
			r.Use(handler.OptionalAuth(authService))
			r.Post("/telemetry", telemetryHandler.PostTelemetry)
		})
		r.Get("/telemetry", telemetryHandler.GetTelemetry)
	})

	server := &http.Server{
		Addr:         fmt.Sprintf(":%s", cfg.Port),
		Handler:      r,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	go func() {
		log.Printf("Дорожный пульс (Road Pulse) Go backend (Auth + Telemetry) слушает порт :%s", cfg.Port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Ошибка HTTP-сервера: %v", err)
		}
	}()

	<-ctx.Done()
	log.Println("Остановка сервиса...")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = server.Shutdown(shutdownCtx)
}
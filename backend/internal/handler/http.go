package handler

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"

	"road_pulse/backend/internal/service"
)

const maxBodyBytes = 256 << 10 // трек из 50 точек укладывается с запасом

func respondJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func respondDetail(w http.ResponseWriter, status int, detail string) {
	respondJSON(w, status, map[string]string{"detail": detail})
}

// respondError маппит ошибки сервисов в HTTP-коды; внутренние детали наружу не отдаём.
func respondError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, service.ErrInvalidTelemetry),
		errors.Is(err, service.ErrInvalidDistance),
		errors.Is(err, service.ErrInvalidComment),
		errors.Is(err, service.ErrInvalidProfile),
		errors.Is(err, service.ErrInvalidPhone),
		errors.Is(err, service.ErrInvalidTrip):
		respondDetail(w, http.StatusBadRequest, err.Error())
	case errors.Is(err, service.ErrInvalidCode),
		errors.Is(err, service.ErrCodeExpired),
		errors.Is(err, service.ErrInvalidToken):
		respondDetail(w, http.StatusUnauthorized, err.Error())
	case errors.Is(err, service.ErrTripNotFound):
		respondDetail(w, http.StatusNotFound, err.Error())
	case errors.Is(err, service.ErrUserNotFound):
		respondDetail(w, http.StatusUnauthorized, "Пользователь не найден, войдите заново")
	case errors.Is(err, service.ErrTooManyAttempts),
		errors.Is(err, service.ErrRateLimited),
		errors.Is(err, service.ErrOTPLocked):
		respondDetail(w, http.StatusTooManyRequests, err.Error())
	default:
		log.Printf("handler: %v", err)
		respondDetail(w, http.StatusInternalServerError, "Внутренняя ошибка сервера")
	}
}

func decodeJSON(w http.ResponseWriter, r *http.Request, dst any) error {
	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	return json.NewDecoder(r.Body).Decode(dst)
}

func userIDFrom(r *http.Request) string {
	id, _ := r.Context().Value(ContextUserIDKey).(string)
	return id
}
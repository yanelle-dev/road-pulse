package handler

import (
	"encoding/json"
	"net/http"

	"road_pulse/backend/internal/models"
	"road_pulse/backend/internal/service"
)

type TripHandler struct {
	service *service.TripService
}

func NewTripHandler(s *service.TripService) *TripHandler {
	return &TripHandler{service: s}
}

func (h *TripHandler) StartTrip(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	userID, ok := r.Context().Value(ContextUserIDKey).(string)
	if !ok || userID == "" {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(map[string]string{"detail": "Требуется авторизация"})
		return
	}

	tripID, err := h.service.StartTrip(r.Context(), userID)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]string{"detail": err.Error()})
		return
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(models.StartTripResponse{TripID: tripID})
}

func (h *TripHandler) FinishTrip(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	userID, ok := r.Context().Value(ContextUserIDKey).(string)
	if !ok || userID == "" {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(map[string]string{"detail": "Требуется авторизация"})
		return
	}

	var payload models.FinishTripPayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil || payload.TripID <= 0 {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"detail": "Некорректный payload завершения поездки"})
		return
	}

	trip, err := h.service.FinishTrip(r.Context(), userID, &payload)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]string{"detail": err.Error()})
		return
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(trip)
}

func (h *TripHandler) GetLastTrip(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	userID, ok := r.Context().Value(ContextUserIDKey).(string)
	if !ok || userID == "" {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(map[string]string{"detail": "Требуется авторизация"})
		return
	}

	trip, err := h.service.GetLastTrip(r.Context(), userID)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]string{"detail": err.Error()})
		return
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(trip)
}
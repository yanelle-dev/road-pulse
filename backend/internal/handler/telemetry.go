package handler

import (
	"encoding/json"
	"net/http"

	"road_pulse/backend/internal/models"
	"road_pulse/backend/internal/service"
)

type TelemetryHandler struct {
	service *service.TelemetryService
}

func NewTelemetryHandler(s *service.TelemetryService) *TelemetryHandler {
	return &TelemetryHandler{service: s}
}

func (h *TelemetryHandler) PostTelemetry(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	var payload models.TelemetryPayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"detail": "Некорректный JSON"})
		return
	}

	if payload.SpeedKMH < service.MinSpeedKMH {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"detail": "Speed too low"})
		return
	}

	// Если пользователь авторизован по JWT, подставляем его реальный ID
	if authUserID, ok := r.Context().Value(ContextUserIDKey).(string); ok && authUserID != "" {
		payload.UserID = authUserID
	} else if payload.UserID == "" {
		payload.UserID = "anonymous"
	}

	resp, err := h.service.SaveTelemetry(r.Context(), &payload)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]string{"detail": err.Error()})
		return
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}

func (h *TelemetryHandler) GetTelemetry(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	clusters, err := h.service.GetClusters(r.Context())
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]string{"detail": err.Error()})
		return
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(clusters)
}
package handler

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

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

func (h *TelemetryHandler) PostDistance(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	var payload models.DistancePayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"detail": "Некорректный JSON"})
		return
	}

	if payload.DistanceMeters <= 0 {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"detail": "Дистанция должна быть больше 0"})
		return
	}

	userID := "anonymous"
	if authUserID, ok := r.Context().Value(ContextUserIDKey).(string); ok && authUserID != "" {
		userID = authUserID
	}

	resp, err := h.service.RecordDistance(r.Context(), userID, payload.DistanceMeters)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]string{"detail": err.Error()})
		return
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}

func (h *TelemetryHandler) GetComments(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	clusterIDStr := r.URL.Query().Get("cluster_id")
	if clusterIDStr == "" {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"detail": "Параметр cluster_id обязателен"})
		return
	}

	var clusterID int64
	if _, err := fmt.Sscanf(clusterIDStr, "%d", &clusterID); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"detail": "Некорректный cluster_id"})
		return
	}

	comments, err := h.service.GetComments(r.Context(), clusterID)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]string{"detail": err.Error()})
		return
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(comments)
}

func (h *TelemetryHandler) PostComment(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	userID, ok := r.Context().Value(ContextUserIDKey).(string)
	if !ok || userID == "" {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(map[string]string{"detail": "Требуется авторизация"})
		return
	}

	var payload models.CreateCommentPayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil || payload.ClusterID <= 0 || strings.TrimSpace(payload.Text) == "" {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"detail": "Передайте корректный cluster_id и текст комментария"})
		return
	}

	// Защита от подмены автора: имя пользователя извлекается из профиля users по токену в БД
	comment, err := h.service.AddComment(r.Context(), payload.ClusterID, userID, "", payload.Text)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]string{"detail": err.Error()})
		return
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(comment)
}
package handler

import (
	"net/http"
	"strconv"
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
	var payload models.TelemetryPayload
	if err := decodeJSON(w, r, &payload); err != nil {
		respondDetail(w, http.StatusBadRequest, "Некорректный JSON")
		return
	}

	if payload.SpeedKMH < service.MinSpeedKMH {
		respondDetail(w, http.StatusBadRequest, "Speed too low")
		return
	}

	// Токен прислан, но не принят (истёк/подделан): запись «как гость» засчитала бы яму
	// не тому пользователю и дала бы ложное подтверждение. Клиент на 401 обновляет токен и повторяет.
	uid := userIDFrom(r)
	if uid == "" && strings.TrimSpace(r.Header.Get("Authorization")) != "" {
		respondDetail(w, http.StatusUnauthorized, "Недействительный токен")
		return
	}
	if uid == "" {
		uid = "anonymous"
	}
	payload.UserID = uid

	resp, err := h.service.SaveTelemetry(r.Context(), &payload)
	if err != nil {
		respondError(w, err)
		return
	}
	respondJSON(w, http.StatusOK, resp)
}

func (h *TelemetryHandler) GetTelemetry(w http.ResponseWriter, r *http.Request) {
	clusters, err := h.service.GetClusters(r.Context())
	if err != nil {
		respondError(w, err)
		return
	}
	respondJSON(w, http.StatusOK, clusters)
}

func (h *TelemetryHandler) PostDistance(w http.ResponseWriter, r *http.Request) {
	var payload models.DistancePayload
	if err := decodeJSON(w, r, &payload); err != nil {
		respondDetail(w, http.StatusBadRequest, "Некорректный JSON")
		return
	}

	if payload.DistanceMeters <= 0 {
		respondDetail(w, http.StatusBadRequest, "Дистанция должна быть больше 0")
		return
	}

	userID := userIDFrom(r)
	// Токен прислан, но не принят (истёк/подделан): раньше это молча превращалось в гостя
	// с ответом 200, и клиент стирал накопленный пробег. Теперь — явный 401.
	if userID == "" && strings.TrimSpace(r.Header.Get("Authorization")) != "" {
		respondDetail(w, http.StatusUnauthorized, "Недействительный токен")
		return
	}
	if userID == "" {
		userID = "anonymous"
	}

	resp, err := h.service.RecordDistance(r.Context(), userID, payload.DistanceMeters)
	if err != nil {
		respondError(w, err)
		return
	}
	respondJSON(w, http.StatusOK, resp)
}

func (h *TelemetryHandler) GetComments(w http.ResponseWriter, r *http.Request) {
	raw := r.URL.Query().Get("cluster_id")
	if raw == "" {
		respondDetail(w, http.StatusBadRequest, "Параметр cluster_id обязателен")
		return
	}

	clusterID, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || clusterID <= 0 {
		respondDetail(w, http.StatusBadRequest, "Некорректный cluster_id")
		return
	}

	comments, err := h.service.GetComments(r.Context(), clusterID)
	if err != nil {
		respondError(w, err)
		return
	}
	respondJSON(w, http.StatusOK, comments)
}

func (h *TelemetryHandler) PostComment(w http.ResponseWriter, r *http.Request) {
	userID := userIDFrom(r)
	if userID == "" {
		respondDetail(w, http.StatusUnauthorized, "Требуется авторизация")
		return
	}

	var payload models.CreateCommentPayload
	if err := decodeJSON(w, r, &payload); err != nil || payload.ClusterID <= 0 || strings.TrimSpace(payload.Text) == "" {
		respondDetail(w, http.StatusBadRequest, "Передайте корректный cluster_id и текст комментария")
		return
	}

	// Имя автора берётся из профиля в БД, поле author_name из тела игнорируется.
	comment, err := h.service.AddComment(r.Context(), payload.ClusterID, userID, "", payload.Text)
	if err != nil {
		respondError(w, err)
		return
	}
	respondJSON(w, http.StatusOK, comment)
}
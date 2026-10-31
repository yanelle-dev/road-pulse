package handler

import (
	"net/http"

	"road_pulse/backend/internal/models"
	"road_pulse/backend/internal/service"
)

type AuthHandler struct {
	service *service.AuthService
}

func NewAuthHandler(s *service.AuthService) *AuthHandler {
	return &AuthHandler{service: s}
}

func (h *AuthHandler) RequestCode(w http.ResponseWriter, r *http.Request) {
	var payload models.RequestCodePayload
	if err := decodeJSON(w, r, &payload); err != nil || payload.Phone == "" {
		respondDetail(w, http.StatusBadRequest, "Укажите корректный номер телефона")
		return
	}

	retryAfter, err := h.service.RequestCode(r.Context(), payload.Phone)
	if err != nil {
		respondError(w, err)
		return
	}
	respondJSON(w, http.StatusOK, map[string]any{"status": "code_sent", "retry_after": retryAfter})
}

func (h *AuthHandler) VerifyCode(w http.ResponseWriter, r *http.Request) {
	var payload models.VerifyCodePayload
	if err := decodeJSON(w, r, &payload); err != nil || payload.Phone == "" || payload.Code == "" {
		respondDetail(w, http.StatusBadRequest, "Передайте номер телефона и код")
		return
	}

	resp, err := h.service.VerifyCode(r.Context(), payload.Phone, payload.Code)
	if err != nil {
		respondError(w, err)
		return
	}
	respondJSON(w, http.StatusOK, resp)
}

func (h *AuthHandler) Refresh(w http.ResponseWriter, r *http.Request) {
	var payload models.RefreshTokenPayload
	if err := decodeJSON(w, r, &payload); err != nil || payload.RefreshToken == "" {
		respondDetail(w, http.StatusBadRequest, "Передайте refresh_token")
		return
	}

	resp, err := h.service.Refresh(r.Context(), payload.RefreshToken)
	if err != nil {
		respondError(w, err)
		return
	}
	respondJSON(w, http.StatusOK, resp)
}

func (h *AuthHandler) GetMe(w http.ResponseWriter, r *http.Request) {
	user, err := h.service.GetProfile(r.Context(), userIDFrom(r))
	if err != nil {
		respondError(w, err)
		return
	}
	respondJSON(w, http.StatusOK, user)
}

func (h *AuthHandler) UpdateMe(w http.ResponseWriter, r *http.Request) {
	var payload models.UpdateProfilePayload
	if err := decodeJSON(w, r, &payload); err != nil {
		respondDetail(w, http.StatusBadRequest, "Некорректный JSON")
		return
	}

	user, err := h.service.UpdateProfile(r.Context(), userIDFrom(r), &payload)
	if err != nil {
		respondError(w, err)
		return
	}
	respondJSON(w, http.StatusOK, user)
}

func (h *AuthHandler) DeleteMe(w http.ResponseWriter, r *http.Request) {
	if err := h.service.DeleteAccount(r.Context(), userIDFrom(r)); err != nil {
		respondError(w, err)
		return
	}
	respondJSON(w, http.StatusOK, map[string]string{"status": "account_deleted"})
}

func (h *AuthHandler) Logout(w http.ResponseWriter, r *http.Request) {
	var payload models.RefreshTokenPayload
	_ = decodeJSON(w, r, &payload)

	if payload.RefreshToken != "" {
		_ = h.service.Logout(r.Context(), payload.RefreshToken)
	}
	respondJSON(w, http.StatusOK, map[string]string{"status": "logged_out"})
}

func (h *AuthHandler) SyncStats(w http.ResponseWriter, r *http.Request) {
	var payload models.SyncStatsPayload
	if err := decodeJSON(w, r, &payload); err != nil {
		respondDetail(w, http.StatusBadRequest, "Некорректный JSON")
		return
	}

	user, err := h.service.SyncStats(r.Context(), userIDFrom(r), payload.StreakDays, payload.UnlockedAchievements)
	if err != nil {
		respondError(w, err)
		return
	}
	respondJSON(w, http.StatusOK, user)
}
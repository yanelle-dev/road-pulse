package handler

import (
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
	tripID, err := h.service.StartTrip(r.Context(), userIDFrom(r))
	if err != nil {
		respondError(w, err)
		return
	}
	respondJSON(w, http.StatusOK, models.StartTripResponse{TripID: tripID})
}

func (h *TripHandler) FinishTrip(w http.ResponseWriter, r *http.Request) {
	var payload models.FinishTripPayload
	if err := decodeJSON(w, r, &payload); err != nil || payload.TripID <= 0 {
		respondDetail(w, http.StatusBadRequest, "Некорректный payload завершения поездки")
		return
	}

	trip, err := h.service.FinishTrip(r.Context(), userIDFrom(r), &payload)
	if err != nil {
		respondError(w, err)
		return
	}
	respondJSON(w, http.StatusOK, trip)
}

func (h *TripHandler) GetLastTrip(w http.ResponseWriter, r *http.Request) {
	trip, err := h.service.GetLastTrip(r.Context(), userIDFrom(r))
	if err != nil {
		respondError(w, err)
		return
	}
	respondJSON(w, http.StatusOK, trip)
}
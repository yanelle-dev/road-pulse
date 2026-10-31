package service

import (
	"errors"
	"math"
	"testing"

	"road_pulse/backend/internal/models"
)

func TestNormalizeTrip(t *testing.T) {
	t.Run("доли приводятся к сумме 1", func(t *testing.T) {
		p := &models.FinishTripPayload{DistanceMeters: 1000, SmoothRatio: 0.8, MediumRatio: 0.5, HardRatio: 0.2}
		if err := normalizeTrip(p); err != nil {
			t.Fatal(err)
		}
		if sum := p.SmoothRatio + p.MediumRatio + p.HardRatio; math.Abs(sum-1) > 1e-9 {
			t.Errorf("сумма долей %.6f, ожидалась 1", sum)
		}
	})

	t.Run("нулевые доли превращаются в «всё ровно»", func(t *testing.T) {
		p := &models.FinishTripPayload{}
		if err := normalizeTrip(p); err != nil {
			t.Fatal(err)
		}
		if p.SmoothRatio != 1 || p.MediumRatio != 0 || p.HardRatio != 0 {
			t.Errorf("получено %+v", p)
		}
	})

	invalid := map[string]models.FinishTripPayload{
		"отрицательная доля": {SmoothRatio: -0.1},
		"доля больше 1":      {SmoothRatio: 1.5},
		"NaN":                {SmoothRatio: math.NaN()},
		"дистанция":          {DistanceMeters: MaxTripDistanceMeters + 1},
		"дефекты":            {DefectsCount: MaxTripDefects + 1},
	}
	for name, p := range invalid {
		t.Run(name, func(t *testing.T) {
			p := p
			if err := normalizeTrip(&p); !errors.Is(err, ErrInvalidTrip) {
				t.Errorf("ожидалась ErrInvalidTrip, получено %v", err)
			}
		})
	}
}
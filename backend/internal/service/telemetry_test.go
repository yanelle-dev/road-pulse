package service

import (
	"errors"
	"math"
	"testing"
	"time"

	"road_pulse/backend/internal/models"
)

func TestCalculateNormalizedForce(t *testing.T) {
	s := &TelemetryService{}

	tests := []struct {
		name      string
		bumpForce float64
		speedKMH  float64
		expected  float64
	}{
		{"speed below threshold 20 kmh clamps to 20", 15.0, 10.0, 15.0},
		{"speed exactly at threshold 20 kmh", 25.0, 20.0, 25.0},
		{"speed 40 kmh halves the force", 30.0, 40.0, 15.0},
		{"speed 80 kmh quarters the force", 40.0, 80.0, 10.0},
		{"zero speed clamped to 20", 20.0, 0.0, 20.0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			res := s.CalculateNormalizedForce(tt.bumpForce, tt.speedKMH)
			if math.Abs(res-tt.expected) > 0.001 {
				t.Errorf("got %.3f, want %.3f", res, tt.expected)
			}
		})
	}
}

func TestSeverityFor(t *testing.T) {
	tests := []struct {
		name       string
		defectType string
		force      float64
		speed      float64
		want       int
	}{
		{"слабый удар на 40 км/ч", "pothole", 10, 40, 1},
		{"заметный удар на 40 км/ч", "pothole", 15, 40, 2},
		{"жёсткий удар на 40 км/ч", "pothole", 25, 40, 3},
		{"порог растёт со скоростью: 30 на 100 км/ч — заметно", "pothole", 30, 100, 2},
		{"45 на 100 км/ч — жёстко", "pothole", 45, 100, 3},
		{"лёгкая тряска", "rough_road", 7.5, 40, 1},
		{"сильная тряска", "rough_road", 18, 40, 2},
		{"очень сильная тряска", "rough_road", 30, 40, 3},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := SeverityFor(tt.defectType, tt.force, tt.speed); got != tt.want {
				t.Errorf("SeverityFor(%s, %.1f, %.0f) = %d, want %d", tt.defectType, tt.force, tt.speed, got, tt.want)
			}
		})
	}
}

func validPayload() *models.TelemetryPayload {
	heading := 90.0
	return &models.TelemetryPayload{
		Latitude:   55.75,
		Longitude:  37.61,
		SpeedKMH:   40,
		BumpForce:  12,
		DefectType: "pothole",
		HeadingDeg: &heading,
		AccuracyM:  8,
	}
}

func TestValidatePayload(t *testing.T) {
	if err := ValidatePayload(validPayload()); err != nil {
		t.Fatalf("валидный payload отклонён: %v", err)
	}

	bad := map[string]func(p *models.TelemetryPayload){
		"широта":       func(p *models.TelemetryPayload) { p.Latitude = 91 },
		"скорость":     func(p *models.TelemetryPayload) { p.SpeedKMH = -1 },
		"сила":         func(p *models.TelemetryPayload) { p.BumpForce = 0 },
		"тип":          func(p *models.TelemetryPayload) { p.DefectType = "crater" },
		"курс":         func(p *models.TelemetryPayload) { h := 360.0; p.HeadingDeg = &h },
		"точность":     func(p *models.TelemetryPayload) { p.AccuracyM = -5 },
		"NaN в силе":   func(p *models.TelemetryPayload) { p.BumpForce = math.NaN() },
		"длинный id":   func(p *models.TelemetryPayload) { p.ClientEventID = string(make([]byte, MaxClientEventIDLen+1)) },
		"длинный трек": func(p *models.TelemetryPayload) { p.Trajectory = make([]models.TrajectoryPoint, MaxTrajectoryPoints+1) },
	}
	for name, mutate := range bad {
		t.Run(name, func(t *testing.T) {
			p := validPayload()
			mutate(p)
			if err := ValidatePayload(p); !errors.Is(err, ErrInvalidTelemetry) {
				t.Errorf("ожидалась ErrInvalidTelemetry, получено %v", err)
			}
		})
	}
}

func TestResolveEventTime(t *testing.T) {
	now := time.Now()

	if resolveEventTime(0) != nil {
		t.Error("нулевое время должно давать nil")
	}
	if resolveEventTime(now.Add(-time.Minute).UnixMilli()) == nil {
		t.Error("минута назад должна приниматься")
	}
	if resolveEventTime(now.Add(-72*time.Hour).UnixMilli()) != nil {
		t.Error("три дня назад должны отбрасываться")
	}
	if resolveEventTime(now.Add(time.Hour).UnixMilli()) != nil {
		t.Error("время из будущего должно отбрасываться")
	}
}

func TestParseGeoJSONCoordinates(t *testing.T) {
	t.Run("empty string returns nil", func(t *testing.T) {
		if res := parseGeoJSONCoordinates(""); res != nil {
			t.Errorf("expected nil, got %v", res)
		}
	})

	t.Run("invalid json returns nil", func(t *testing.T) {
		if res := parseGeoJSONCoordinates("invalid-json"); res != nil {
			t.Errorf("expected nil, got %v", res)
		}
	})

	t.Run("LineString coordinates parsed and swapped to lat-lon", func(t *testing.T) {
		raw := `{"type":"LineString","coordinates":[[37.6184, 55.7512], [37.6190, 55.7520]]}`
		res := parseGeoJSONCoordinates(raw)
		if len(res) != 2 {
			t.Fatalf("expected 2 points, got %d", len(res))
		}
		if res[0][0] != 55.7512 || res[0][1] != 37.6184 {
			t.Errorf("expected [55.7512, 37.6184], got %v", res[0])
		}
		if res[1][0] != 55.7520 || res[1][1] != 37.6190 {
			t.Errorf("expected [55.7520, 37.6190], got %v", res[1])
		}
	})

	t.Run("MultiLineString coordinates flattened and swapped", func(t *testing.T) {
		raw := `{"type":"MultiLineString","coordinates":[[[37.61, 55.75]], [[37.62, 55.76]]]}`
		res := parseGeoJSONCoordinates(raw)
		if len(res) != 2 {
			t.Fatalf("expected 2 points, got %d", len(res))
		}
		if res[0][0] != 55.75 || res[0][1] != 37.61 {
			t.Errorf("expected [55.75, 37.61], got %v", res[0])
		}
	})
}

func TestParseGeoJSONLines(t *testing.T) {
	t.Run("MultiLineString остаётся отдельными линиями", func(t *testing.T) {
		raw := `{"type":"MultiLineString","coordinates":[[[37.61,55.75],[37.62,55.76]],[[37.70,55.80],[37.71,55.81]]]}`
		lines := parseGeoJSONLines(raw)
		if len(lines) != 2 {
			t.Fatalf("expected 2 lines, got %d", len(lines))
		}
		if len(lines[0]) != 2 || lines[0][0][0] != 55.75 || lines[0][0][1] != 37.61 {
			t.Errorf("первая линия разобрана неверно: %v", lines[0])
		}
		if lines[1][1][0] != 55.81 || lines[1][1][1] != 37.71 {
			t.Errorf("вторая линия разобрана неверно: %v", lines[1])
		}
	})

	t.Run("LineString даёт одну линию", func(t *testing.T) {
		lines := parseGeoJSONLines(`{"type":"LineString","coordinates":[[37.61,55.75],[37.62,55.76]]}`)
		if len(lines) != 1 || len(lines[0]) != 2 {
			t.Errorf("expected 1 line of 2 points, got %v", lines)
		}
	})

	t.Run("пустой и битый ввод", func(t *testing.T) {
		if parseGeoJSONLines("") != nil || parseGeoJSONLines("not-json") != nil {
			t.Error("expected nil")
		}
	})
}
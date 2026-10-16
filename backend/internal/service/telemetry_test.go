package service

import (
	"math"
	"testing"
)

func TestCalculateNormalizedForce(t *testing.T) {
	s := &TelemetryService{}

	tests := []struct {
		name      string
		bumpForce float64
		speedKMH  float64
		expected  float64
	}{
		{
			name:      "speed below threshold 20 kmh clamps to 20",
			bumpForce: 15.0,
			speedKMH:  10.0,
			expected:  15.0, // 15 * (20 / max(10, 20)) = 15.0
		},
		{
			name:      "speed exactly at threshold 20 kmh",
			bumpForce: 25.0,
			speedKMH:  20.0,
			expected:  25.0, // 25 * (20 / 20) = 25.0
		},
		{
			name:      "speed 40 kmh halves the force",
			bumpForce: 30.0,
			speedKMH:  40.0,
			expected:  15.0, // 30 * (20 / 40) = 15.0
		},
		{
			name:      "speed 80 kmh quarters the force",
			bumpForce: 40.0,
			speedKMH:  80.0,
			expected:  10.0, // 40 * (20 / 80) = 10.0
		},
		{
			name:      "zero speed clamped to 20",
			bumpForce: 20.0,
			speedKMH:  0.0,
			expected:  20.0,
		},
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

func TestParseGeoJSONCoordinates(t *testing.T) {
	t.Run("empty string returns nil", func(t *testing.T) {
		res := parseGeoJSONCoordinates("")
		if res != nil {
			t.Errorf("expected nil, got %v", res)
		}
	})

	t.Run("invalid json returns nil", func(t *testing.T) {
		res := parseGeoJSONCoordinates("invalid-json")
		if res != nil {
			t.Errorf("expected nil, got %v", res)
		}
	})

	t.Run("LineString coordinates parsed and swapped to lat-lon", func(t *testing.T) {
		raw := `{"type":"LineString","coordinates":[[37.6184, 55.7512], [37.6190, 55.7520]]}`
		res := parseGeoJSONCoordinates(raw)
		if len(res) != 2 {
			t.Fatalf("expected 2 points, got %d", len(res))
		}
		// PostGIS GeoJSON хранит [lon, lat], парсер переводит в [lat, lon]
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
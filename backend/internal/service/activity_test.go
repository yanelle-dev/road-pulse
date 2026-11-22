package service

import (
	"testing"
	"time"

	"road_pulse/backend/internal/models"
)

func TestActivityStreak(t *testing.T) {
	today := time.Date(2026, 11, 9, 0, 0, 0, 0, time.UTC)
	day := func(date string, meters float64, defects int) models.ActivityDay {
		return models.ActivityDay{Date: date, DistanceMeters: meters, Defects: defects}
	}

	cases := []struct {
		name string
		days []models.ActivityDay
		want int
	}{
		{"пусто", nil, 0},
		{"только сегодня", []models.ActivityDay{day("2026-11-09", 120, 0)}, 1},
		{"сегодня ещё не ездил", []models.ActivityDay{day("2026-11-08", 0, 2), day("2026-11-07", 50, 0)}, 2},
		{"разрыв", []models.ActivityDay{day("2026-11-09", 10, 0), day("2026-11-07", 10, 0)}, 1},
		{"позавчера не считается", []models.ActivityDay{day("2026-11-07", 10, 0)}, 0},
		{"нулевой день не активен", []models.ActivityDay{day("2026-11-09", 0, 0), day("2026-11-08", 5, 0)}, 1},
		{"через границу месяца", []models.ActivityDay{day("2026-11-01", 1, 0), day("2026-10-31", 1, 0)}, 0},
	}
	for _, c := range cases {
		if got := ActivityStreak(c.days, today); got != c.want {
			t.Errorf("%s: ActivityStreak = %d, want %d", c.name, got, c.want)
		}
	}

	monthEdge := []models.ActivityDay{day("2026-11-01", 1, 0), day("2026-10-31", 1, 0)}
	if got := ActivityStreak(monthEdge, time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC)); got != 2 {
		t.Errorf("граница месяца: ActivityStreak = %d, want 2", got)
	}
}

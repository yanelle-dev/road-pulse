package osrm

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"strings"
	"sync"
	"time"

	"road_pulse/backend/internal/models"
)

const (
	requestTimeout = 5 * time.Second
	maxBodyBytes   = 1 << 20

	// Дальше этого расстояния точка скорее вне дорожного графа (двор, парковка):
	// привязка к ближайшей дороге исказила бы координаты.
	nearestMaxSnapMeters = 40
	// Допуск курса: сегмент дороги выбирается по направлению движения, а не только по расстоянию.
	nearestBearingRange = 45
	// Дефолт OSRM — 5 м, что меньше типичной погрешности GPS в городе.
	matchRadiusMeters = 25

	breakerFailThreshold = 5
	breakerOpenFor       = 30 * time.Second
)

// breaker отключает OSRM на время, если публичный сервер лежит или режет частоту:
// иначе каждый приём телеметрии ждал бы полный таймаут.
type breaker struct {
	mu        sync.Mutex
	fails     int
	openUntil time.Time
}

func (b *breaker) allow() bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	return time.Now().After(b.openUntil)
}

func (b *breaker) record(ok bool) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if ok {
		b.fails = 0
		return
	}
	b.fails++
	if b.fails >= breakerFailThreshold {
		b.openUntil = time.Now().Add(breakerOpenFor)
		b.fails = 0
	}
}

// Snap — результат привязки точки к дорожному графу.
type Snap struct {
	Lat, Lon float64
	Name     string // название дороги; пусто, если OSRM его не знает или привязки не было
}

type Client struct {
	baseURL    string
	httpClient *http.Client
	breaker    breaker
}

func NewClient(baseURL string) *Client {
	return &Client{
		baseURL:    strings.TrimRight(baseURL, "/"),
		httpClient: &http.Client{Timeout: requestTimeout},
	}
}

// get возвращает тело ответа и статус. 400 (NoSegment/NoMatch) — штатный ответ OSRM,
// а не сбой сервиса, поэтому на состояние breaker он не влияет.
func (c *Client) get(ctx context.Context, url string) ([]byte, int, bool) {
	if !c.breaker.allow() {
		return nil, 0, false
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, 0, false
	}
	resp, err := c.httpClient.Do(req)
	if err != nil {
		c.breaker.record(false)
		return nil, 0, false
	}
	defer resp.Body.Close()

	serverFault := resp.StatusCode >= 500 || resp.StatusCode == http.StatusTooManyRequests
	c.breaker.record(!serverFault)
	if serverFault {
		return nil, resp.StatusCode, false
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxBodyBytes))
	if err != nil {
		return nil, resp.StatusCode, false
	}
	return body, resp.StatusCode, true
}

// Nearest привязывает одиночную точку к дорожному графу. С курсом сначала ищется
// сегмент по направлению движения (параллельные дороги, эстакады, съезды), затем — любой.
// При сбое или слишком далёкой дороге возвращаются исходные координаты, чтобы не терять попадание.
func (c *Client) Nearest(ctx context.Context, lat, lon float64, headingDeg *float64) Snap {
	if headingDeg != nil {
		bearing := (int(math.Round(*headingDeg))%360 + 360) % 360
		extra := fmt.Sprintf("&bearings=%d,%d", bearing, nearestBearingRange)
		if s, ok := c.nearest(ctx, lat, lon, extra); ok {
			return s
		}
	}
	if s, ok := c.nearest(ctx, lat, lon, ""); ok {
		return s
	}
	return Snap{Lat: lat, Lon: lon}
}

func (c *Client) nearest(ctx context.Context, lat, lon float64, extraQuery string) (Snap, bool) {
	url := fmt.Sprintf("%s/nearest/v1/driving/%f,%f?number=1%s", c.baseURL, lon, lat, extraQuery)
	body, status, ok := c.get(ctx, url)
	if !ok || status != http.StatusOK {
		return Snap{}, false
	}

	var data struct {
		Code      string `json:"code"`
		Waypoints []struct {
			Location []float64 `json:"location"` // [lon, lat]
			Distance float64   `json:"distance"`
			Name     string    `json:"name"`
		} `json:"waypoints"`
	}
	if err := json.Unmarshal(body, &data); err != nil || data.Code != "Ok" || len(data.Waypoints) == 0 {
		return Snap{}, false
	}

	wp := data.Waypoints[0]
	if len(wp.Location) < 2 || wp.Distance > nearestMaxSnapMeters {
		return Snap{}, false
	}
	return Snap{Lat: wp.Location[1], Lon: wp.Location[0], Name: strings.TrimSpace(wp.Name)}, true
}

// Match выполняет map-matching трека и возвращает самую частую в треке дорогу.
// OSRM требует строго возрастающих timestamps, поэтому точки в одну секунду разводятся на +1 с.
func (c *Client) Match(ctx context.Context, trajectory []models.TrajectoryPoint) (wkt, geomType, roadName string, ok bool) {
	if len(trajectory) < 2 {
		return "", "", "", false
	}

	coords := make([]string, 0, len(trajectory))
	timestamps := make([]string, 0, len(trajectory))
	radiuses := make([]string, 0, len(trajectory))
	prevTS := int64(-1)
	for _, p := range trajectory {
		ts := int64(p.Timestamp)
		if ts <= prevTS {
			ts = prevTS + 1
		}
		prevTS = ts
		coords = append(coords, fmt.Sprintf("%f,%f", p.Lon, p.Lat))
		timestamps = append(timestamps, fmt.Sprintf("%d", ts))
		radiuses = append(radiuses, fmt.Sprintf("%d", matchRadiusMeters))
	}

	url := fmt.Sprintf(
		"%s/match/v1/driving/%s?geometries=geojson&overview=full&timestamps=%s&radiuses=%s",
		c.baseURL,
		strings.Join(coords, ";"),
		strings.Join(timestamps, ";"),
		strings.Join(radiuses, ";"),
	)
	body, status, got := c.get(ctx, url)
	if !got || status != http.StatusOK {
		return "", "", "", false
	}

	var data struct {
		Code      string `json:"code"`
		Matchings []struct {
			Geometry struct {
				Type        string          `json:"type"`
				Coordinates json.RawMessage `json:"coordinates"`
			} `json:"geometry"`
		} `json:"matchings"`
		Tracepoints []*struct {
			Name string `json:"name"`
		} `json:"tracepoints"` // непривязанные точки приходят как null
	}
	if err := json.Unmarshal(body, &data); err != nil || data.Code != "Ok" {
		return "", "", "", false
	}

	// Трек может распасться на несколько сегментов; берём самый длинный.
	var best [][]float64
	for _, m := range data.Matchings {
		if m.Geometry.Type != "LineString" {
			continue
		}
		var pts [][]float64
		if err := json.Unmarshal(m.Geometry.Coordinates, &pts); err == nil && len(pts) > len(best) {
			best = pts
		}
	}
	if len(best) < 2 {
		return "", "", "", false
	}

	points := make([]string, 0, len(best))
	for _, pt := range best {
		if len(pt) >= 2 {
			points = append(points, fmt.Sprintf("%.7f %.7f", pt[0], pt[1]))
		}
	}
	if len(points) < 2 {
		return "", "", "", false
	}

	counts := map[string]int{}
	for _, tp := range data.Tracepoints {
		if tp != nil && strings.TrimSpace(tp.Name) != "" {
			counts[strings.TrimSpace(tp.Name)]++
		}
	}
	top := 0
	for name, n := range counts {
		if n > top {
			top, roadName = n, name
		}
	}

	return fmt.Sprintf("LINESTRING(%s)", strings.Join(points, ", ")), "LineString", roadName, true
}
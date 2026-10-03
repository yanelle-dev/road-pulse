package osrm

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"road_pulse/backend/internal/models"
)

type Client struct {
	baseURL    string
	httpClient *http.Client
}

func NewClient(baseURL string) *Client {
	return &Client{
		baseURL: strings.TrimRight(baseURL, "/"),
		httpClient: &http.Client{
			Timeout: 5 * time.Second,
		},
	}
}

// Nearest привязывает одиночную точку к дорожному графу OSRM
func (c *Client) Nearest(ctx context.Context, lat, lon float64) (float64, float64) {
	url := fmt.Sprintf("%s/nearest/v1/driving/%f,%f", c.baseURL, lon, lat)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return lat, lon
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return lat, lon
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return lat, lon
	}

	var data struct {
		Code      string `json:"code"`
		Waypoints []struct {
			Location []float64 `json:"location"` // [lon, lat]
		} `json:"waypoints"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
		return lat, lon
	}

	if data.Code == "Ok" && len(data.Waypoints) > 0 && len(data.Waypoints[0].Location) >= 2 {
		return data.Waypoints[0].Location[1], data.Waypoints[0].Location[0]
	}

	return lat, lon
}

// Match выполняет map-matching трека из нескольких точек
func (c *Client) Match(ctx context.Context, trajectory []models.TrajectoryPoint) (string, string, bool) {
	if len(trajectory) < 2 {
		return "", "", false
	}

	var coords []string
	var timestamps []string
	for _, p := range trajectory {
		coords = append(coords, fmt.Sprintf("%f,%f", p.Lon, p.Lat))
		timestamps = append(timestamps, fmt.Sprintf("%d", int64(p.Timestamp)))
	}

	url := fmt.Sprintf(
		"%s/match/v1/driving/%s?geometries=geojson&overview=full&timestamps=%s",
		c.baseURL,
		strings.Join(coords, ";"),
		strings.Join(timestamps, ";"),
	)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return "", "", false
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", "", false
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", "", false
	}

	var data struct {
		Code      string `json:"code"`
		Matchings []struct {
			Geometry struct {
				Type        string      `json:"type"`
				Coordinates interface{} `json:"coordinates"`
			} `json:"geometry"`
		} `json:"matchings"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil || data.Code != "Ok" || len(data.Matchings) == 0 {
		return "", "", false
	}

	geom := data.Matchings[0].Geometry
	switch geom.Type {
	case "LineString":
		if rawCoords, ok := geom.Coordinates.([]interface{}); ok && len(rawCoords) >= 2 {
			var pts []string
			for _, item := range rawCoords {
				if pt, ok := item.([]interface{}); ok && len(pt) >= 2 {
					pts = append(pts, fmt.Sprintf("%v %v", pt[0], pt[1]))
				}
			}
			if len(pts) >= 2 {
				return fmt.Sprintf("LINESTRING(%s)", strings.Join(pts, ", ")), "LineString", true
			}
		}
	case "Point":
		if pt, ok := geom.Coordinates.([]interface{}); ok && len(pt) >= 2 {
			return fmt.Sprintf("POINT(%v %v)", pt[0], pt[1]), "Point", true
		}
	}

	return "", "", false
}
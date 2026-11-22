package service

import (
	"context"
	"testing"

	"road_pulse/backend/internal/sms"
)

type stubProvider struct{}

func (stubProvider) SendCode(context.Context, string, string) error { return nil }

func TestExposeOTPOnlyWithMockProvider(t *testing.T) {
	cases := []struct {
		name     string
		provider sms.Provider
		expose   bool
		want     bool
	}{
		{"mock и флаг", sms.NewMockProvider(), true, true},
		{"mock без флага", sms.NewMockProvider(), false, false},
		{"боевой шлюз и флаг", stubProvider{}, true, false},
	}
	for _, c := range cases {
		s := NewAuthService(nil, "test_secret_key_for_otp_exposure_checks", c.provider, c.expose, "Europe/Moscow")
		if s.exposeOTP != c.want {
			t.Errorf("%s: exposeOTP = %v, want %v", c.name, s.exposeOTP, c.want)
		}
	}
}

package sms

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"road_pulse/backend/internal/config"
)

const (
	gateRequestTimeout = 10 * time.Second
	maxErrorBodyBytes  = 512
)

// Provider описывает интерфейс отправки сервисных SMS-сообщений
type Provider interface {
	SendCode(ctx context.Context, phone, code string) error
}

// MockProvider логирует код в консоль/журнал (режим разработки и тестирования)
type MockProvider struct{}

func NewMockProvider() *MockProvider {
	return &MockProvider{}
}

func (m *MockProvider) SendCode(ctx context.Context, phone, code string) error {
	log.Printf("==================================================")
	log.Printf("📱 [SMS-GATEWAY] Телефон: %s | Код: %s", phone, code)
	log.Printf("==================================================")
	return nil
}

// GateProvider отправляет SMS через SMS Gateway for Android (облако api.sms-gate.app
// или локальный сервер на телефоне): сообщение уходит с SIM-карты этого телефона.
type GateProvider struct {
	baseURL  string
	user     string
	password string
	client   *http.Client
}

func NewGateProvider(baseURL, user, password string) *GateProvider {
	return &GateProvider{
		baseURL:  strings.TrimRight(baseURL, "/"),
		user:     user,
		password: password,
		client:   &http.Client{Timeout: gateRequestTimeout},
	}
}

func (g *GateProvider) SendCode(ctx context.Context, phone, code string) error {
	body, err := json.Marshal(map[string]any{
		"textMessage":  map[string]string{"text": "Дорожный пульс: код " + code},
		"phoneNumbers": []string{phone},
	})
	if err != nil {
		return fmt.Errorf("ошибка сборки запроса к SMS-шлюзу: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, g.baseURL+"/message", bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("ошибка запроса к SMS-шлюзу: %w", err)
	}
	req.SetBasicAuth(g.user, g.password)
	req.Header.Set("Content-Type", "application/json")

	resp, err := g.client.Do(req)
	if err != nil {
		return fmt.Errorf("SMS-шлюз недоступен: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		snippet, _ := io.ReadAll(io.LimitReader(resp.Body, maxErrorBodyBytes))
		return fmt.Errorf("SMS-шлюз вернул %d: %s", resp.StatusCode, strings.TrimSpace(string(snippet)))
	}
	return nil
}

// NewProvider выбирает GateProvider при заданных SMS_GATE_USER/SMS_GATE_PASSWORD.
// В production запуск без них запрещён: тихий фолбэк на вывод кодов в лог открыл бы вход всем.
func NewProvider(cfg *config.Config) Provider {
	if cfg.SMSGateUser != "" && cfg.SMSGatePassword != "" {
		return NewGateProvider(cfg.SMSGateURL, cfg.SMSGateUser, cfg.SMSGatePassword)
	}

	if env := strings.ToLower(cfg.AppEnv); env == "production" || env == "prod" {
		log.Fatal("Критическая ошибка: в production обязательны SMS_GATE_USER и SMS_GATE_PASSWORD. Запуск с мок-провайдером запрещён.")
	}

	log.Println("⚠️ ВНИМАНИЕ: SMS_GATE_USER не задан. Используется MockProvider (коды печатаются в лог сервера).")
	return NewMockProvider()
}
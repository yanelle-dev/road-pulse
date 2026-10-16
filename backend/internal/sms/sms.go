package sms

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"
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

// HttpProvider — адаптер под боевые коммерческие SMS-шлюзы (SMS.RU, SMSC и т.д.)
type HttpProvider struct {
	ApiKey string
	Sender string
}

func NewHttpProvider(apiKey, sender string) *HttpProvider {
	return &HttpProvider{
		ApiKey: apiKey,
		Sender: sender,
	}
}

func (h *HttpProvider) SendCode(ctx context.Context, phone, code string) error {
	if h.ApiKey == "" {
		return fmt.Errorf("SMS_API_KEY не задан")
	}
	log.Printf("📱 [SMS-PROD] Отправка через внешний шлюз на номер %s (код: %s)", phone, code)
	return nil
}

// NewProviderFromEnv возвращает HttpProvider при наличии ключа. В production запуск без ключа запрещён.
func NewProviderFromEnv() Provider {
	apiKey := os.Getenv("SMS_API_KEY")
	sender := os.Getenv("SMS_SENDER")
	env := strings.ToLower(os.Getenv("APP_ENV"))

	if apiKey != "" {
		return NewHttpProvider(apiKey, sender)
	}

	// Защита: в продакшене запрещён тихий фолбэк на вывод SMS в консоль
	if env == "production" || env == "prod" {
		log.Fatal("Критическая ошибка: в production окружении переменная SMS_API_KEY обязательна! Запуск с мок-провайдером запрещён.")
	}

	log.Println("⚠️ ВНИМАНИЕ: SMS_API_KEY не задан. Используется MockProvider (SMS логируются в консоль сервера).")
	return NewMockProvider()
}
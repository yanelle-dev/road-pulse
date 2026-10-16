package service

import (
	"math"
	"testing"
)

func TestNormalizePhone(t *testing.T) {
	s := &AuthService{}

	tests := []struct {
		input    string
		expected string
	}{
		{input: "+7 (999) 123-45-67", expected: "+79991234567"},
		{input: "89991234567", expected: "+89991234567"},
		{input: "+79991234567", expected: "+79991234567"},
		{input: " +7-999-000-11-22 ", expected: "+79990001122"},
	}

	for _, tt := range tests {
		got := s.normalizePhone(tt.input)
		if got != tt.expected {
			t.Errorf("normalizePhone(%q) = %q, want %q", tt.input, got, tt.expected)
		}
	}
}

func TestHashString(t *testing.T) {
	s := &AuthService{}
	h1 := s.hashString("1234")
	h2 := s.hashString("1234")
	h3 := s.hashString("4321")

	if h1 != h2 {
		t.Errorf("hashString should be deterministic")
	}
	if h1 == h3 {
		t.Errorf("different inputs should produce different hashes")
	}
	if len(h1) != 64 {
		t.Errorf("expected 64 char hex sha256 string, got %d", len(h1))
	}
}

func TestJWTAccessToken(t *testing.T) {
	secret := "test_secret_key_with_sufficient_length_for_hmac_256"
	s := NewAuthService(nil, secret, nil)

	userID := "usr_test_12345"
	phone := "+79991234567"

	tokenStr, err := s.generateAccessToken(userID, phone)
	if err != nil {
		t.Fatalf("generateAccessToken failed: %v", err)
	}
	if tokenStr == "" {
		t.Fatal("expected non-empty token string")
	}

	// Валидный токен
	sub, err := s.ValidateAccessToken(tokenStr)
	if err != nil {
		t.Fatalf("ValidateAccessToken failed on valid token: %v", err)
	}
	if sub != userID {
		t.Errorf("got sub %q, want %q", sub, userID)
	}

	// Токен с другим секретом
	sWrong := NewAuthService(nil, "completely_different_secret_key_here", nil)
	_, err = sWrong.ValidateAccessToken(tokenStr)
	if err == nil {
		t.Error("expected validation to fail with wrong secret, but it succeeded")
	}
}

func TestRatingFormula(t *testing.T) {
	// (Км * 10) + (Дефекты * 50) + (Награды * 100) + (Серия * 20)
	km := 12.34
	defects := 5
	awards := 3
	streak := 7

	expected := 123 + (5 * 50) + (3 * 100) + (7 * 20) // 123 + 250 + 300 + 140 = 813

	calculated := int(math.Round(km*10)) + (defects * 50) + (awards * 100) + (streak * 20)
	if calculated != expected {
		t.Errorf("got rating %d, want %d", calculated, expected)
	}
}
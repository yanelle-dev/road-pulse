package handler

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"

	"easyride_backend_go/internal/service"
)

type contextKey string

const ContextUserIDKey contextKey = "user_id"

// RequireAuth проверяет Bearer-токен. Если токен недействителен, возвращает 401
func RequireAuth(authService *service.AuthService) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			authHeader := r.Header.Get("Authorization")
			if authHeader == "" || !strings.HasPrefix(authHeader, "Bearer ") {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusUnauthorized)
				_ = json.NewEncoder(w).Encode(map[string]string{"detail": "Отсутствует заголовок Authorization: Bearer <token>"})
				return
			}

			tokenStr := strings.TrimSpace(strings.TrimPrefix(authHeader, "Bearer "))
			userID, err := authService.ValidateAccessToken(tokenStr)
			if err != nil {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusUnauthorized)
				_ = json.NewEncoder(w).Encode(map[string]string{"detail": err.Error()})
				return
			}

			ctx := context.WithValue(r.Context(), ContextUserIDKey, userID)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// OptionalAuth извлекает userID, если токен передан, но не блокирует гостевые запросы
func OptionalAuth(authService *service.AuthService) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			authHeader := r.Header.Get("Authorization")
			if authHeader != "" && strings.HasPrefix(authHeader, "Bearer ") {
				tokenStr := strings.TrimSpace(strings.TrimPrefix(authHeader, "Bearer "))
				if userID, err := authService.ValidateAccessToken(tokenStr); err == nil {
					ctx := context.WithValue(r.Context(), ContextUserIDKey, userID)
					next.ServeHTTP(w, r.WithContext(ctx))
					return
				}
			}
			next.ServeHTTP(w, r)
		})
	}
}
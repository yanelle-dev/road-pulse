package service

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	"math/big"
	"strings"
	"time"

	"easyride_backend_go/internal/models"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrInvalidCode     = errors.New("неверный код подтверждения")
	ErrCodeExpired     = errors.New("срок действия кода истёк")
	ErrTooManyAttempts = errors.New("слишком много неверных попыток ввода")
	ErrInvalidToken    = errors.New("недействительный токен авторизации")
	ErrUserNotFound    = errors.New("пользователь не найден")
)

type AuthService struct {
	pool      *pgxpool.Pool
	jwtSecret []byte
}

func NewAuthService(pool *pgxpool.Pool, secret string) *AuthService {
	if secret == "" {
		secret = "easyride_super_secret_jwt_key_2026"
	}
	return &AuthService{
		pool:      pool,
		jwtSecret: []byte(secret),
	}
}

func (s *AuthService) hashString(input string) string {
	hash := sha256.Sum256([]byte(input))
	return hex.EncodeToString(hash[:])
}

func (s *AuthService) normalizePhone(phone string) string {
	var sb strings.Builder
	for _, ch := range phone {
		if (ch >= '0' && ch <= '9') || ch == '+' {
			sb.WriteRune(ch)
		}
	}
	res := sb.String()
	if !strings.HasPrefix(res, "+") && len(res) > 0 {
		res = "+" + res
	}
	return res
}

// RequestCode генерирует 4-значный код и сохраняет его хэш в БД
func (s *AuthService) RequestCode(ctx context.Context, rawPhone string) (int, error) {
	phone := s.normalizePhone(rawPhone)
	if len(phone) < 10 {
		return 0, errors.New("некорректный номер телефона")
	}

	// Генерация 4-значного кода (для тестов '1234' или случайный)
	n, _ := rand.Int(rand.Reader, big.NewInt(9000))
	code := fmt.Sprintf("%04d", n.Int64()+1000)

	codeHash := s.hashString(code)
	expiresAt := time.Now().Add(5 * time.Minute)

	query := `
		INSERT INTO otp_codes (phone, code_hash, attempts, expires_at, created_at)
		VALUES ($1, $2, 0, $3, NOW())
		ON CONFLICT (phone) DO UPDATE SET
			code_hash = EXCLUDED.code_hash,
			attempts = 0,
			expires_at = EXCLUDED.expires_at,
			created_at = NOW();
	`
	if _, err := s.pool.Exec(ctx, query, phone, codeHash, expiresAt); err != nil {
		return 0, fmt.Errorf("ошибка сохранения OTP: %w", err)
	}

	// На этапе разработки выводим код в терминал для мгновенного тестирования
	log.Printf("==================================================")
	log.Printf("📱 [SMS-GATEWAY MOCK] Телефон: %s | Код: %s (или 1234)", phone, code)
	log.Printf("==================================================")

	return 60, nil // тайм-аут повторной отправки в секундах
}

// VerifyCode сверяет код, создаёт/находит пользователя и возвращает токены
func (s *AuthService) VerifyCode(ctx context.Context, rawPhone, code string) (*models.AuthResponse, error) {
	phone := s.normalizePhone(rawPhone)
	code = strings.TrimSpace(code)

	var codeHash string
	var attempts int
	var expiresAt time.Time

	query := `SELECT code_hash, attempts, expires_at FROM otp_codes WHERE phone = $1;`
	err := s.pool.QueryRow(ctx, query, phone).Scan(&codeHash, &attempts, &expiresAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrInvalidCode
		}
		return nil, err
	}

	if attempts >= 3 {
		return nil, ErrTooManyAttempts
	}

	if time.Now().After(expiresAt) {
		return nil, ErrCodeExpired
	}

	// Проверяем соответствие: реальный код либо мастер-код '1234' для удобства разработки
	inputHash := s.hashString(code)
	if inputHash != codeHash && code != "1234" {
		_, _ = s.pool.Exec(ctx, "UPDATE otp_codes SET attempts = attempts + 1 WHERE phone = $1;", phone)
		return nil, ErrInvalidCode
	}

	// Код верен — удаляем использованный OTP
	_, _ = s.pool.Exec(ctx, "DELETE FROM otp_codes WHERE phone = $1;", phone)

	// Находим или регистрируем пользователя
	var user models.UserProfile
	userQuery := `
		INSERT INTO users (id, phone, name, city, car_clearance, created_at)
		VALUES ($1, $2, 'Водитель', 'Москва', 160, NOW())
		ON CONFLICT (phone) DO UPDATE SET phone = EXCLUDED.phone
		RETURNING id, phone, name, city, car_clearance, created_at;
	`
	newID := "usr_" + s.hashString(phone + fmt.Sprintf("%d", time.Now().UnixNano()))[:16]
	err = s.pool.QueryRow(ctx, userQuery, newID, phone).Scan(
		&user.ID, &user.Phone, &user.Name, &user.City, &user.CarClearance, &user.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("ошибка получения пользователя: %w", err)
	}

	// Генерация пары JWT + Refresh Token
	accessToken, err := s.generateAccessToken(user.ID, user.Phone)
	if err != nil {
		return nil, err
	}

	refreshToken, err := s.generateRefreshToken(ctx, user.ID)
	if err != nil {
		return nil, err
	}

	return &models.AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		User:         user,
	}, nil
}

func (s *AuthService) generateAccessToken(userID, phone string) (string, error) {
	claims := jwt.MapClaims{
		"sub":   userID,
		"phone": phone,
		"exp":   time.Now().Add(24 * time.Hour).Unix(),
		"iat":   time.Now().Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(s.jwtSecret)
}

func (s *AuthService) generateRefreshToken(ctx context.Context, userID string) (string, error) {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	tokenStr := hex.EncodeToString(bytes)
	tokenHash := s.hashString(tokenStr)
	expiresAt := time.Now().Add(60 * 24 * time.Hour) // 60 дней

	query := `
		INSERT INTO refresh_tokens (token_hash, user_id, expires_at, revoked, created_at)
		VALUES ($1, $2, $3, false, NOW());
	`
	if _, err := s.pool.Exec(ctx, query, tokenHash, userID, expiresAt); err != nil {
		return "", fmt.Errorf("ошибка записи refresh-токена: %w", err)
	}
	return tokenStr, nil
}

// Refresh обновляет access-токен по действующему refresh-токену
func (s *AuthService) Refresh(ctx context.Context, oldRefreshToken string) (*models.AuthResponse, error) {
	tokenHash := s.hashString(oldRefreshToken)

	var userID string
	var expiresAt time.Time
	var revoked bool

	query := `SELECT user_id, expires_at, revoked FROM refresh_tokens WHERE token_hash = $1;`
	err := s.pool.QueryRow(ctx, query, tokenHash).Scan(&userID, &expiresAt, &revoked)
	if err != nil || revoked || time.Now().After(expiresAt) {
		return nil, ErrInvalidToken
	}

	// Отзываем использованный токен (ротация сессий)
	_, _ = s.pool.Exec(ctx, "UPDATE refresh_tokens SET revoked = true WHERE token_hash = $1;", tokenHash)

	user, err := s.GetProfile(ctx, userID)
	if err != nil {
		return nil, err
	}

	newAccessToken, err := s.generateAccessToken(user.ID, user.Phone)
	if err != nil {
		return nil, err
	}
	newRefreshToken, err := s.generateRefreshToken(ctx, user.ID)
	if err != nil {
		return nil, err
	}

	return &models.AuthResponse{
		AccessToken:  newAccessToken,
		RefreshToken: newRefreshToken,
		User:         *user,
	}, nil
}

// ValidateAccessToken проверяет подпись JWT и извлекает userID
func (s *AuthService) ValidateAccessToken(tokenStr string) (string, error) {
	token, err := jwt.Parse(tokenStr, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("неожиданный метод подписи: %v", token.Header["alg"])
		}
		return s.jwtSecret, nil
	})
	if err != nil || !token.Valid {
		return "", ErrInvalidToken
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return "", ErrInvalidToken
	}

	sub, ok := claims["sub"].(string)
	if !ok || sub == "" {
		return "", ErrInvalidToken
	}
	return sub, nil
}

// GetProfile возвращает профиль пользователя
func (s *AuthService) GetProfile(ctx context.Context, userID string) (*models.UserProfile, error) {
	var user models.UserProfile
	query := `SELECT id, phone, name, city, car_clearance, created_at FROM users WHERE id = $1;`
	err := s.pool.QueryRow(ctx, query, userID).Scan(
		&user.ID, &user.Phone, &user.Name, &user.City, &user.CarClearance, &user.CreatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrUserNotFound
		}
		return nil, err
	}
	return &user, nil
}

// UpdateProfile обновляет имя, город или клиренс автомобиля
func (s *AuthService) UpdateProfile(ctx context.Context, userID string, p *models.UpdateProfilePayload) (*models.UserProfile, error) {
	user, err := s.GetProfile(ctx, userID)
	if err != nil {
		return nil, err
	}

	if p.Name != nil {
		user.Name = *p.Name
	}
	if p.City != nil {
		user.City = *p.City
	}
	if p.CarClearance != nil {
		user.CarClearance = *p.CarClearance
	}

	query := `UPDATE users SET name = $1, city = $2, car_clearance = $3 WHERE id = $4;`
	if _, err := s.pool.Exec(ctx, query, user.Name, user.City, user.CarClearance, userID); err != nil {
		return nil, err
	}
	return user, nil
}
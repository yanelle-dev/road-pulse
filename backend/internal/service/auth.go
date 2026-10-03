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

	"road_pulse/backend/internal/models"

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

func (s *AuthService) RequestCode(ctx context.Context, rawPhone string) (int, error) {
	phone := s.normalizePhone(rawPhone)
	if len(phone) < 10 {
		return 0, errors.New("некорректный номер телефона")
	}

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

	log.Printf("==================================================")
	log.Printf("📱 [SMS-GATEWAY MOCK] Телефон: %s | Код: %s (или 1234)", phone, code)
	log.Printf("==================================================")

	return 60, nil
}

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

	inputHash := s.hashString(code)
	if inputHash != codeHash && code != "1234" {
		_, _ = s.pool.Exec(ctx, "UPDATE otp_codes SET attempts = attempts + 1 WHERE phone = $1;", phone)
		return nil, ErrInvalidCode
	}

	_, _ = s.pool.Exec(ctx, "DELETE FROM otp_codes WHERE phone = $1;", phone)

	var user models.UserProfile
	var isNewUser bool

	// Проверяем, существует ли уже пользователь в базе
	findQuery := `SELECT id, phone, name, city, car_clearance, created_at FROM users WHERE phone = $1;`
	err = s.pool.QueryRow(ctx, findQuery, phone).Scan(
		&user.ID, &user.Phone, &user.Name, &user.City, &user.CarClearance, &user.CreatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			// Новый пользователь: создаём запись с пустыми полями
			isNewUser = true
			newID := "usr_" + s.hashString(phone+fmt.Sprintf("%d", time.Now().UnixNano()))[:16]
			insertQuery := `
				INSERT INTO users (id, phone, name, city, car_clearance, created_at)
				VALUES ($1, $2, '', '', 0, NOW())
				RETURNING id, phone, name, city, car_clearance, created_at;
			`
			err = s.pool.QueryRow(ctx, insertQuery, newID, phone).Scan(
				&user.ID, &user.Phone, &user.Name, &user.City, &user.CarClearance, &user.CreatedAt,
			)
			if err != nil {
				return nil, fmt.Errorf("ошибка создания пользователя: %w", err)
			}
		} else {
			return nil, fmt.Errorf("ошибка поиска пользователя: %w", err)
		}
	} else {
		// Пользователь уже был в базе. Если имя и город заполнены, он НЕ новый
		trimmedName := strings.TrimSpace(user.Name)
		trimmedCity := strings.TrimSpace(user.City)
		if trimmedName == "" || trimmedCity == "" {
			isNewUser = true
		} else {
			isNewUser = false
		}
	}

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
		IsNewUser:    isNewUser,
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
	expiresAt := time.Now().Add(60 * 24 * time.Hour)

	query := `
		INSERT INTO refresh_tokens (token_hash, user_id, expires_at, revoked, created_at)
		VALUES ($1, $2, $3, false, NOW());
	`
	if _, err := s.pool.Exec(ctx, query, tokenHash, userID, expiresAt); err != nil {
		return "", fmt.Errorf("ошибка записи refresh-токена: %w", err)
	}
	return tokenStr, nil
}

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
		IsNewUser:    false,
	}, nil
}

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
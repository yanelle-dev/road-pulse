package service

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	"math"
	"math/big"
	"strings"
	"time"

	"road_pulse/backend/internal/models"
	"road_pulse/backend/internal/sms"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrInvalidCode     = errors.New("неверный код подтверждения")
	ErrCodeExpired     = errors.New("срок действия кода истёк")
	ErrTooManyAttempts = errors.New("слишком много неверных попыток ввода")
	ErrRateLimited     = errors.New("повторный запрос кода возможен через 60 секунд")
	ErrInvalidToken    = errors.New("недействительный токен авторизации")
	ErrUserNotFound    = errors.New("пользователь не найден")
)

type AuthService struct {
	pool      *pgxpool.Pool
	jwtSecret []byte
	sms       sms.Provider
}

func NewAuthService(pool *pgxpool.Pool, secret string, smsProvider sms.Provider) *AuthService {
	if secret == "" {
		log.Println("JWT_SECRET не задан! Использован временный ключ для разработки.")
		secret = "dev_only_road_pulse_jwt_secret_key_insecure"
	}
	if smsProvider == nil {
		smsProvider = sms.NewMockProvider()
	}
	return &AuthService{
		pool:      pool,
		jwtSecret: []byte(secret),
		sms:       smsProvider,
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

	var lastCreatedAt time.Time
	checkQuery := `SELECT created_at FROM otp_codes WHERE phone = $1;`
	if err := s.pool.QueryRow(ctx, checkQuery, phone).Scan(&lastCreatedAt); err == nil {
		if time.Since(lastCreatedAt) < 60*time.Second {
			return 0, ErrRateLimited
		}
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

	if err := s.sms.SendCode(ctx, phone, code); err != nil {
		return 0, fmt.Errorf("ошибка отправки SMS: %w", err)
	}

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
	if inputHash != codeHash {
		_, _ = s.pool.Exec(ctx, "UPDATE otp_codes SET attempts = attempts + 1 WHERE phone = $1;", phone)
		return nil, ErrInvalidCode
	}

	_, _ = s.pool.Exec(ctx, "DELETE FROM otp_codes WHERE phone = $1;", phone)

	var user models.UserProfile
	var isNewUser bool

	findQuery := `
		SELECT 
			id, phone, name, city, car_clearance, 
			COALESCE(total_distance_meters, 0), streak_days, unlocked_achievements, created_at 
		FROM users 
		WHERE phone = $1;
	`
	err = s.pool.QueryRow(ctx, findQuery, phone).Scan(
		&user.ID, &user.Phone, &user.Name, &user.City, &user.CarClearance, 
		&user.TotalDistanceMeters, &user.StreakDays, &user.UnlockedAchievements, &user.CreatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			isNewUser = true
			newID := "usr_" + s.hashString(phone+fmt.Sprintf("%d", time.Now().UnixNano()))[:16]
			insertQuery := `
				INSERT INTO users (id, phone, name, city, car_clearance, total_distance_meters, streak_days, unlocked_achievements, created_at)
				VALUES ($1, $2, '', '', 0, 0, 0, 0, NOW())
				RETURNING id, phone, name, city, car_clearance, total_distance_meters, streak_days, unlocked_achievements, created_at;
			`
			err = s.pool.QueryRow(ctx, insertQuery, newID, phone).Scan(
				&user.ID, &user.Phone, &user.Name, &user.City, &user.CarClearance, 
				&user.TotalDistanceMeters, &user.StreakDays, &user.UnlockedAchievements, &user.CreatedAt,
			)
			if err != nil {
				return nil, fmt.Errorf("ошибка создания пользователя: %w", err)
			}
		} else {
			return nil, fmt.Errorf("ошибка поиска пользователя: %w", err)
		}
	} else {
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

	if fullProfile, err := s.GetProfile(ctx, user.ID); err == nil {
		user = *fullProfile
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
	query := `
		SELECT 
			id, phone, name, city, car_clearance, 
			COALESCE(total_distance_meters, 0), streak_days, unlocked_achievements, created_at 
		FROM users 
		WHERE id = $1;
	`
	err := s.pool.QueryRow(ctx, query, userID).Scan(
		&user.ID, &user.Phone, &user.Name, &user.City, &user.CarClearance, 
		&user.TotalDistanceMeters, &user.StreakDays, &user.UnlockedAchievements, &user.CreatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrUserNotFound
		}
		return nil, err
	}

	var defectsCount int
	defectsQuery := `SELECT COUNT(*)::int FROM telemetry WHERE user_id = $1;`
	_ = s.pool.QueryRow(ctx, defectsQuery, userID).Scan(&defectsCount)
	user.TotalDefects = defectsCount

	km := user.TotalDistanceMeters / 1000.0
	user.Rating = int(math.Round(km*10)) +
		(defectsCount * 50) +
		(user.UnlockedAchievements * 100) +
		(user.StreakDays * 20)

	user.SavedSuspensions = int(math.Ceil(float64(defectsCount) * 0.15))

	if user.TotalDistanceMeters > 0 || user.TotalDefects > 0 {
		percentileQuery := `
			WITH active_users AS (
				SELECT 
					u.id,
					(ROUND(COALESCE(u.total_distance_meters, 0) / 100.0) + 
					 (COUNT(t.id) * 50) + 
					 (u.unlocked_achievements * 100) + 
					 (u.streak_days * 20)) AS score
				FROM users u
				LEFT JOIN telemetry t ON t.user_id = u.id
				WHERE COALESCE(u.total_distance_meters, 0) > 0 OR t.id IS NOT NULL
				GROUP BY u.id, u.total_distance_meters, u.unlocked_achievements, u.streak_days
			),
			ranked AS (
				SELECT 
					id,
					PERCENT_RANK() OVER (ORDER BY score DESC) AS prank
				FROM active_users
			)
			SELECT prank FROM ranked WHERE id = $1;
		`
		var prank float64
		if err := s.pool.QueryRow(ctx, percentileQuery, userID).Scan(&prank); err == nil {
			pct := int(math.Ceil(prank * 100))
			if pct < 1 {
				pct = 1
			}
			user.CommunityPercentile = pct
		}
	} else {
		user.CommunityPercentile = 0
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

	query := `
		UPDATE users 
		SET name = $1, city = $2, car_clearance = $3 
		WHERE id = $4;
	`
	if _, err := s.pool.Exec(ctx, query, user.Name, user.City, user.CarClearance, userID); err != nil {
		return nil, err
	}
	return s.GetProfile(ctx, userID)
}

func (s *AuthService) SyncStats(ctx context.Context, userID string, streakDays, unlockedAchievements int) (*models.UserProfile, error) {
	query := `
		UPDATE users 
		SET streak_days = $1, unlocked_achievements = $2 
		WHERE id = $3;
	`
	if _, err := s.pool.Exec(ctx, query, streakDays, unlockedAchievements, userID); err != nil {
		return nil, fmt.Errorf("ошибка синхронизации статистики пользователя: %w", err)
	}
	return s.GetProfile(ctx, userID)
}

func (s *AuthService) DeleteAccount(ctx context.Context, userID string) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("ошибка запуска транзакции: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx, `UPDATE telemetry SET user_id = 'anonymous' WHERE user_id = $1;`, userID); err != nil {
		return fmt.Errorf("ошибка анонимизации телеметрии: %w", err)
	}

	if _, err := tx.Exec(ctx, `DELETE FROM users WHERE id = $1;`, userID); err != nil {
		return fmt.Errorf("ошибка удаления пользователя: %w", err)
	}

	return tx.Commit(ctx)
}

func (s *AuthService) Logout(ctx context.Context, refreshToken string) error {
	if refreshToken == "" {
		return nil
	}
	tokenHash := s.hashString(refreshToken)
	_, err := s.pool.Exec(ctx, "UPDATE refresh_tokens SET revoked = true WHERE token_hash = $1;", tokenHash)
	return err
}
package service

import (
	"context"
	"crypto/hmac"
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
	"unicode/utf8"

	"road_pulse/backend/internal/models"
	"road_pulse/backend/internal/sms"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	otpTTL            = 5 * time.Minute
	otpMaxAttempts    = 3
	otpResendSeconds  = 60
	otpLockoutMinutes = 15

	accessTokenTTL    = 24 * time.Hour
	refreshTokenTTL   = 60 * 24 * time.Hour
	refreshKeepRevokedDays = 7

	minPhoneDigits = 10
	maxPhoneDigits = 15

	maxProfileTextRunes = 100
	maxCarClearance     = 600

	// Значения приходят с клиента и входят в рейтинг, поэтому ограничены правдоподобным максимумом.
	MaxStreakDays   = 3650
	MaxAchievements = 30

	minJWTSecretLen = 32
)

var (
	ErrInvalidCode     = errors.New("неверный код подтверждения")
	ErrCodeExpired     = errors.New("срок действия кода истёк")
	ErrTooManyAttempts = errors.New("слишком много неверных попыток ввода")
	ErrRateLimited     = errors.New("повторный запрос кода возможен через 60 секунд")
	ErrOTPLocked       = errors.New("слишком много неверных попыток, повторите через 15 минут")
	ErrInvalidPhone    = errors.New("некорректный номер телефона")
	ErrInvalidProfile  = errors.New("некорректные данные профиля")
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
	} else if len(secret) < minJWTSecretLen {
		log.Printf("JWT_SECRET короче %d символов: ключ легко подобрать", minJWTSecretLen)
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

// hashOTP — HMAC с секретом и номером: четырёхзначный код без соли подбирается из дампа БД мгновенно.
func (s *AuthService) hashOTP(phone, code string) string {
	mac := hmac.New(sha256.New, s.jwtSecret)
	mac.Write([]byte(phone + ":" + code))
	return hex.EncodeToString(mac.Sum(nil))
}

// normalizePhone оставляет только цифры, приводит российское «8…» к «+7…» и добавляет «+».
func (s *AuthService) normalizePhone(phone string) string {
	var sb strings.Builder
	for _, ch := range phone {
		if ch >= '0' && ch <= '9' {
			sb.WriteRune(ch)
		}
	}
	digits := sb.String()
	if len(digits) == 11 && digits[0] == '8' {
		digits = "7" + digits[1:]
	}
	if digits == "" {
		return ""
	}
	return "+" + digits
}

func validPhone(phone string) bool {
	n := len(phone) - 1
	return n >= minPhoneDigits && n <= maxPhoneDigits
}

func generateOTP() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(10000))
	if err != nil {
		return "", fmt.Errorf("ошибка генерации кода: %w", err)
	}
	return fmt.Sprintf("%04d", n.Int64()), nil
}

// RequestCode выпускает код и возвращает паузу до повторной отправки (секунды).
// Окно повтора проверяется атомарно прямо в UPSERT; после исчерпания попыток ввода
// новый код выдаётся только через otpLockoutMinutes, иначе короткий код перебирается.
func (s *AuthService) RequestCode(ctx context.Context, rawPhone string) (int, error) {
	phone := s.normalizePhone(rawPhone)
	if !validPhone(phone) {
		return 0, ErrInvalidPhone
	}

	code, err := generateOTP()
	if err != nil {
		return 0, err
	}

	query := `
		INSERT INTO otp_codes (phone, code_hash, attempts, expires_at, created_at)
		VALUES ($1, $2, 0, $3, NOW())
		ON CONFLICT (phone) DO UPDATE SET
			code_hash = EXCLUDED.code_hash,
			attempts = 0,
			expires_at = EXCLUDED.expires_at,
			created_at = NOW()
		WHERE otp_codes.created_at <= NOW() - CASE
			WHEN otp_codes.attempts >= $4::int THEN make_interval(mins => $5::int)
			ELSE make_interval(secs => $6::float8)
		END;
	`
	tag, err := s.pool.Exec(ctx, query,
		phone, s.hashOTP(phone, code), time.Now().Add(otpTTL),
		otpMaxAttempts, otpLockoutMinutes, float64(otpResendSeconds),
	)
	if err != nil {
		return 0, fmt.Errorf("ошибка сохранения OTP: %w", err)
	}
	if tag.RowsAffected() == 0 {
		var attempts int
		_ = s.pool.QueryRow(ctx, `SELECT attempts FROM otp_codes WHERE phone = $1;`, phone).Scan(&attempts)
		if attempts >= otpMaxAttempts {
			return 0, ErrOTPLocked
		}
		return 0, ErrRateLimited
	}

	if err := s.sms.SendCode(ctx, phone, code); err != nil {
		_, _ = s.pool.Exec(ctx, `DELETE FROM otp_codes WHERE phone = $1;`, phone)
		return 0, fmt.Errorf("ошибка отправки SMS: %w", err)
	}
	return otpResendSeconds, nil
}

// VerifyCode списывает попытку одним UPDATE до сравнения: параллельные запросы
// не могут обойти лимит попыток.
func (s *AuthService) VerifyCode(ctx context.Context, rawPhone, code string) (*models.AuthResponse, error) {
	phone := s.normalizePhone(rawPhone)
	code = strings.TrimSpace(code)

	var codeHash string
	var expiresAt time.Time
	err := s.pool.QueryRow(ctx, `
		UPDATE otp_codes SET attempts = attempts + 1
		WHERE phone = $1 AND attempts < $2::int
		RETURNING code_hash, expires_at;
	`, phone, otpMaxAttempts).Scan(&codeHash, &expiresAt)
	if errors.Is(err, pgx.ErrNoRows) {
		var exists bool
		_ = s.pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM otp_codes WHERE phone = $1);`, phone).Scan(&exists)
		if exists {
			return nil, ErrTooManyAttempts
		}
		return nil, ErrInvalidCode
	}
	if err != nil {
		return nil, fmt.Errorf("ошибка проверки OTP: %w", err)
	}

	if time.Now().After(expiresAt) {
		return nil, ErrCodeExpired
	}
	if !hmac.Equal([]byte(s.hashOTP(phone, code)), []byte(codeHash)) {
		return nil, ErrInvalidCode
	}
	_, _ = s.pool.Exec(ctx, `DELETE FROM otp_codes WHERE phone = $1;`, phone)

	userID, isNewUser, err := s.findOrCreateUser(ctx, phone)
	if err != nil {
		return nil, err
	}

	accessToken, err := s.generateAccessToken(userID, phone)
	if err != nil {
		return nil, err
	}
	refreshToken, err := s.generateRefreshToken(ctx, userID)
	if err != nil {
		return nil, err
	}
	user, err := s.GetProfile(ctx, userID)
	if err != nil {
		return nil, err
	}

	return &models.AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		User:         *user,
		IsNewUser:    isNewUser,
	}, nil
}

// findOrCreateUser: ON CONFLICT закрывает гонку двух одновременных входов нового номера.
func (s *AuthService) findOrCreateUser(ctx context.Context, phone string) (string, bool, error) {
	newID := "usr_" + s.hashString(phone+fmt.Sprintf("%d", time.Now().UnixNano()))[:16]
	var id, name, city string
	err := s.pool.QueryRow(ctx, `
		INSERT INTO users (id, phone, name, city, car_clearance, total_distance_meters, streak_days, unlocked_achievements, created_at)
		VALUES ($1, $2, '', '', 0, 0, 0, 0, NOW())
		ON CONFLICT (phone) DO UPDATE SET phone = EXCLUDED.phone
		RETURNING id, name, city;
	`, newID, phone).Scan(&id, &name, &city)
	if err != nil {
		return "", false, fmt.Errorf("ошибка поиска или создания пользователя: %w", err)
	}
	isNew := strings.TrimSpace(name) == "" || strings.TrimSpace(city) == ""
	return id, isNew, nil
}

func (s *AuthService) generateAccessToken(userID, phone string) (string, error) {
	claims := jwt.MapClaims{
		"sub":   userID,
		"phone": phone,
		"exp":   time.Now().Add(accessTokenTTL).Unix(),
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

	// Отозванные токены живут ещё неделю: два изолята приложения могут обновиться одновременно.
	_, _ = s.pool.Exec(ctx, `
		DELETE FROM refresh_tokens
		WHERE user_id = $1 AND (revoked OR expires_at < NOW())
		  AND created_at < NOW() - make_interval(days => $2::int);
	`, userID, refreshKeepRevokedDays)

	query := `
		INSERT INTO refresh_tokens (token_hash, user_id, expires_at, revoked, created_at)
		VALUES ($1, $2, $3, false, NOW());
	`
	if _, err := s.pool.Exec(ctx, query, tokenHash, userID, time.Now().Add(refreshTokenTTL)); err != nil {
		return "", fmt.Errorf("ошибка записи refresh-токена: %w", err)
	}
	return tokenStr, nil
}

// Refresh ротирует токен; отзыв — одним условным UPDATE, поэтому один refresh не обменять дважды.
func (s *AuthService) Refresh(ctx context.Context, oldRefreshToken string) (*models.AuthResponse, error) {
	var userID string
	err := s.pool.QueryRow(ctx, `
		UPDATE refresh_tokens SET revoked = true
		WHERE token_hash = $1 AND NOT revoked AND expires_at > NOW()
		RETURNING user_id;
	`, s.hashString(oldRefreshToken)).Scan(&userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrInvalidToken
	}
	if err != nil {
		return nil, fmt.Errorf("ошибка обновления токена: %w", err)
	}

	user, err := s.getUser(ctx, userID)
	if err != nil {
		return nil, err
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
		User:         *user,
		IsNewUser:    false,
	}, nil
}

func (s *AuthService) ValidateAccessToken(tokenStr string) (string, error) {
	token, err := jwt.Parse(tokenStr, func(*jwt.Token) (interface{}, error) {
		return s.jwtSecret, nil
	}, jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}))
	if err != nil || !token.Valid {
		return "", ErrInvalidToken
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return "", ErrInvalidToken
	}
	if exp, err := claims.GetExpirationTime(); err != nil || exp == nil {
		return "", ErrInvalidToken
	}

	sub, ok := claims["sub"].(string)
	if !ok || sub == "" {
		return "", ErrInvalidToken
	}
	return sub, nil
}

// getUser читает только строку users, без статистики: тяжёлые подсчёты нужны одному GetProfile.
func (s *AuthService) getUser(ctx context.Context, userID string) (*models.UserProfile, error) {
	var user models.UserProfile
	err := s.pool.QueryRow(ctx, `
		SELECT
			id, phone, name, city, car_clearance,
			COALESCE(total_distance_meters, 0), streak_days, unlocked_achievements, created_at
		FROM users
		WHERE id = $1;
	`, userID).Scan(
		&user.ID, &user.Phone, &user.Name, &user.City, &user.CarClearance,
		&user.TotalDistanceMeters, &user.StreakDays, &user.UnlockedAchievements, &user.CreatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrUserNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("ошибка чтения пользователя: %w", err)
	}
	return &user, nil
}

func (s *AuthService) GetProfile(ctx context.Context, userID string) (*models.UserProfile, error) {
	user, err := s.getUser(ctx, userID)
	if err != nil {
		return nil, err
	}

	var defectsCount int
	_ = s.pool.QueryRow(ctx, `SELECT COUNT(*)::int FROM telemetry WHERE user_id = $1;`, userID).Scan(&defectsCount)
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
			user.CommunityPercentile = max(1, int(math.Ceil(prank*100)))
		}
	}

	return user, nil
}

func validProfileText(s string) bool {
	return utf8.RuneCountInString(s) <= maxProfileTextRunes
}

func (s *AuthService) UpdateProfile(ctx context.Context, userID string, p *models.UpdateProfilePayload) (*models.UserProfile, error) {
	var name, city *string
	if p.Name != nil {
		v := strings.TrimSpace(*p.Name)
		if !validProfileText(v) {
			return nil, ErrInvalidProfile
		}
		name = &v
	}
	if p.City != nil {
		v := strings.TrimSpace(*p.City)
		if !validProfileText(v) {
			return nil, ErrInvalidProfile
		}
		city = &v
	}
	if p.CarClearance != nil && (*p.CarClearance < 0 || *p.CarClearance > maxCarClearance) {
		return nil, ErrInvalidProfile
	}

	tag, err := s.pool.Exec(ctx, `
		UPDATE users
		SET name = COALESCE($1::text, name),
		    city = COALESCE($2::text, city),
		    car_clearance = COALESCE($3::int, car_clearance)
		WHERE id = $4;
	`, name, city, p.CarClearance, userID)
	if err != nil {
		return nil, fmt.Errorf("ошибка обновления профиля: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return nil, ErrUserNotFound
	}
	return s.GetProfile(ctx, userID)
}

func (s *AuthService) SyncStats(ctx context.Context, userID string, streakDays, unlockedAchievements int) (*models.UserProfile, error) {
	streakDays = min(max(streakDays, 0), MaxStreakDays)
	unlockedAchievements = min(max(unlockedAchievements, 0), MaxAchievements)

	tag, err := s.pool.Exec(ctx, `
		UPDATE users
		SET streak_days = $1, unlocked_achievements = $2
		WHERE id = $3;
	`, streakDays, unlockedAchievements, userID)
	if err != nil {
		return nil, fmt.Errorf("ошибка синхронизации статистики пользователя: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return nil, ErrUserNotFound
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
	_, err := s.pool.Exec(ctx, `UPDATE refresh_tokens SET revoked = true WHERE token_hash = $1;`, s.hashString(refreshToken))
	return err
}
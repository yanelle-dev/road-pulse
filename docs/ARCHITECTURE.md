# Архитектура «Дорожного пульса»

Карта исходников монорепозитория: **роль файла** и **публичные сущности**.  
Платформенные и генерируемые каталоги (`app/android/`, `app/ios/`, `app/build/`, `.dart_tool/` и т.п.) здесь не расписываются — править их без явной нужды не нужно.

См. также: [README.md](./README.md) · [AGENTS.md](./AGENTS.md)

## 📒 Содержание

- [Общая схема](#-общая-схема)
- [Структура репозитория](#-структура-репозитория)
- [Сервис телеметрии](#-сервис-телеметрии)
- [Клиент](#-клиент)
- [Потоки данных](#-потоки-данных)
- [Границы модулей](#-границы-модулей)

## 🗺️ Общая схема

```mermaid
sequenceDiagram
  participant Accel as Акселерометр
  participant Sensor as SensorTaskHandler (isolate)
  participant API as ApiService
  participant BE as Go chi: handler → service
  participant OSRM as OSRM match/nearest
  participant DB as PostGIS
  participant Map as MapScreen

  Accel->>Sensor: userAccelerometerEventStream
  Sensor->>Sensor: Вертикаль по гравитации, окно удара 600 мс, отсев торможения, полицейских (по ширине импульса в метрах) и вращения
  Sensor->>Sensor: Позиция на момент пика (интерполяция между фиксами GPS), курс, буфер трека (10 точек)
  Sensor->>API: sendDefectStatus(lat, lon, speed, force, defectType, heading, accuracy, trajectory)
  API->>BE: POST /api/v1/telemetry (Bearer, если есть сессия)
  BE->>OSRM: rough_road → /match, pothole → /nearest с курсом (название дороги сохраняется)
  BE->>BE: CalculateNormalizedForce
  BE->>DB: дедуп повторного проезда (15 м / 2 ч), INSERT telemetry (POINT или LINESTRING) с severity, идемпотентно по (user_id, client_event_id)
  Map->>API: getBumps()
  API->>BE: GET /api/v1/telemetry
  BE->>DB: ST_ClusterDBSCAN в метрах (кэш 15 с)
  BE-->>Map: clusters (is_confirmed, max_force, ...)
```

Авторизация:

```mermaid
sequenceDiagram
  participant Screen as AuthScreen
  participant API as ApiService
  participant Auth as handler.AuthHandler
  participant Svc as service.AuthService
  participant DB as PostGIS

  Screen->>API: requestCode(phone)
  API->>Auth: POST /api/v1/auth/request-code
  Auth->>Svc: RequestCode
  Svc->>DB: UPSERT otp_codes (HMAC кода, TTL 5 мин, повтор не раньше 60 с)
  Screen->>API: verifyCode(phone, code)
  API->>Auth: POST /api/v1/auth/verify-code
  Auth->>Svc: VerifyCode
  Svc->>DB: users (создание при необходимости) + refresh_tokens
  Svc-->>Screen: access + refresh + profile + is_new_user
```

## 📁 Структура репозитория

```
road_pulse/
├── app/                  # Flutter-клиент (package road_pulse)
│   ├── assets/fonts/     # Unbounded, Onest, JetBrains Mono
│   ├── assets/icon/      # logo.png
│   └── lib/              # исходники UI и сервисов
├── backend/              # Go 1.25 API (module road_pulse/backend)
│   ├── cmd/api/          # точка входа
│   └── internal/         # config, database, models, osrm, sms, service, handler
└── docs/                 # README.md, ARCHITECTURE.md, AGENTS.md
```

## 🧱 Сервис телеметрии

```
backend/
├── cmd/api/main.go                  # сборка зависимостей, chi-роутер, graceful shutdown
├── internal/config/config.go        # Config + Load() из ENV, падает без обязательных переменных
├── internal/database/database.go    # пул pgx, применение схемы
├── internal/models/telemetry.go     # DTO телеметрии, пробега и комментариев
├── internal/models/auth.go          # DTO авторизации, профиля и статистики
├── internal/models/trip.go          # DTO поездок
├── internal/osrm/client.go          # HTTP-клиент OSRM
├── internal/sms/sms.go              # Provider: GateProvider (SMS Gateway for Android) и MockProvider
├── internal/service/telemetry.go    # бизнес-логика дефектов, кластеры, комментарии
├── internal/service/auth.go         # OTP, JWT, профиль, рейтинг, процентиль
├── internal/service/trip.go         # старт, финиш (валидация, доли приводятся к сумме 1, только своя незавершённая поездка) и чтение
├── internal/service/*_test.go       # unit-тесты формул, телефона, хеша и токенов
├── internal/handler/telemetry.go    # HTTP-обработчики телеметрии и комментариев
├── internal/handler/auth.go         # HTTP-обработчики авторизации и профиля
├── internal/handler/trip.go         # HTTP-обработчики поездок
├── internal/handler/middleware.go   # RequireAuth / OptionalAuth
├── internal/handler/http.go         # respondJSON/respondError (маппинг ошибок сервисов в коды), decodeJSON, userIDFrom
├── internal/handler/ratelimit.go    # RateLimiter (скользящее окно) и middleware RateLimit
├── .env.example                     # шаблон переменных окружения
├── Dockerfile                       # multi-stage: сборка Go → alpine
├── docker-compose.yaml              # postgis/postgis:15-3.3 + api
└── go.mod / go.sum
```

### cmd/api/main.go

Порядок старта: `config.Load()` → `database.Connect` → `database.InitSchema` → сборка OSRM-клиента, сервисов и обработчиков → chi-роутер → `http.Server` (read/write timeout 10 с) → ожидание `SIGINT`/`SIGTERM` с 5-секундным shutdown.

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `main()` | function | Точка входа, wiring, graceful shutdown |
| `GET /health` | inline handler | `SELECT PostGIS_Version()`; `200 {status, postgis}` либо `503 {detail}` |
| Роутер | `chi.Router` | `middleware.Logger`, `middleware.Recoverer` |
| Роуты `/api/v1/auth` | group | `request-code` (5 за 10 мин с IP), `verify-code` (20 за 10 мин), `refresh`, `logout`; под `RequireAuth` — `GET`/`PATCH`/`DELETE /me` и `POST /sync-stats` |
| Роуты `/api/v1/trips` | group | `POST /start`, `POST /finish`, `GET /last` под `RequireAuth` |
| Роут `/api/v1/telemetry` | group | `POST` (120/мин) и `POST /distance` (90/мин) под `OptionalAuth`, `GET` без авторизации, комментарии: `GET` публично и `POST` (10/мин) под `RequireAuth`. Лимиты — по пользователю из JWT, для гостей по IP (`trustProxy` в `main.go`) |

### internal/config/config.go

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `Config` | struct | `AppEnv`, `Port`, `DatabaseURL`, `OSRMBase`, `JWTSecret`, `TrustProxy`, `SMSGateURL`, `SMSGateUser`, `SMSGatePassword` |
| `Load()` | func | Чтение ENV; `DATABASE_URL` и `JWT_SECRET` обязательны (`log.Fatal` с подсказкой про `.env.example`); `APP_ENV` по умолчанию `development`; у OSRM читаются оба имени — `OSRM_BASE` и `OSRM_BASE_URL` |

Секрет JWT приходит в `main.go` из `cfg.JWTSecret` — отдельного `os.Getenv("JWT_SECRET")` больше нет. Провайдер SMS выбирается в `main.go` через `sms.NewProvider(cfg)`: при заданных `SMS_GATE_USER` и `SMS_GATE_PASSWORD` это `GateProvider`, в `production` без них — `log.Fatal`, иначе `MockProvider` с предупреждением в лог. `cfg.TrustProxy` передаётся в `RateLimit`.

### internal/database/database.go

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `Connect(ctx, dbURL)` | func → `*pgxpool.Pool` | Разбор DSN, `MaxConns=25`, `MinConns=2`, idle 5 мин, `Ping` с таймаутом 5 с |
| `InitSchema(ctx, pool)` | func | Идемпотентные миграции: `CREATE EXTENSION postgis`, таблицы, индексы (`idx_telemetry_user_id`, GIST по `location`, `idx_telemetry_type_time`, `idx_telemetry_user_type_time`, `ux_telemetry_user_event`, `idx_users_phone`); старым строкам `severity` проставляется по прежним порогам |

| Таблица | Ключевые поля |
|---------|---------------|
| `telemetry` | `id`, `user_id`, `location GEOMETRY(Geometry,4326)`, `speed_kmh`, `bump_force` (нормализованная), `raw_bump_force`, `severity` (1–3), `road_name`, `defect_type`, `infrastructure_type`, `timestamp` (время события с устройства, если правдоподобно), `client_event_id` (UNIQUE вместе с `user_id`, идемпотентность) |
| `users` | `id VARCHAR(64)` PK, `phone` UNIQUE, `name`, `city`, `car_clearance`, `total_distance_meters`, `streak_days`, `unlocked_achievements`, `created_at` |
| `otp_codes` | `phone` PK, `code_hash` (sha256), `attempts`, `expires_at`, `created_at` |
| `refresh_tokens` | `token_hash` PK, `user_id → users(id) ON DELETE CASCADE`, `expires_at`, `revoked`, `created_at` |
| `trips` | `id`, `user_id → users(id)`, `started_at`, `ended_at`, `distance_meters`, `defects_count`, `smooth_ratio`, `medium_ratio`, `hard_ratio`, `created_at` |
| `defect_comments` | `id`, `cluster_id`, `user_id`, `author_name`, `text`, `created_at` (индекс `idx_defect_comments_cluster_id`) |

### internal/models/telemetry.go

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `TrajectoryPoint` | struct | `lat`, `lon`, `timestamp` |
| `TelemetryPayload` | struct | Вход POST: `user_id`, `latitude`, `longitude`, `speed_kmh`, `bump_force`, `defect_type`, `infrastructure_type`, `trajectory`, `event_time_ms`, `client_event_id`, `heading_deg`, `accuracy_m` |
| `TelemetryResponse` | struct | Ответ POST: `status`, `id`, `snapped_lat`/`snapped_lon`, нормализованный `bump_force`, `severity`, `road_name`, типы дефекта и инфраструктуры, `geometry_type`, `duplicate` |
| `TelemetryCluster` | struct | Элемент ответа GET: `cluster_id`, `lat`, `lon`, `max_force`, `severity`, `unique_users`, `total_hits`, `is_confirmed`, `defect_type`, `infrastructure_type`, `road_name`, `created_at`, `lines`, `coordinates` (для линий) |
| `DistancePayload` | struct | Вход `POST /telemetry/distance`: `distance_meters` |
| `DistanceResponse` | struct | Ответ: `status`, `added_meters`, `total_distance_meters` (накопленный итог пользователя) |
| `DefectComment` | struct | Комментарий: `id`, `cluster_id`, `user_id`, `author_name`, `text`, `created_at` |
| `CreateCommentPayload` | struct | Вход `POST /telemetry/comments`: `cluster_id`, `text`, `author_name` |

### internal/models/auth.go

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `RequestCodePayload` | struct | `phone` |
| `VerifyCodePayload` | struct | `phone`, `code` |
| `RefreshTokenPayload` | struct | `refresh_token` |
| `UserProfile` | struct | `id`, `phone`, `name`, `city`, `car_clearance`, `total_distance_meters`, `total_defects`, `rating`, `saved_suspensions`, `community_percentile`, `streak_days`, `unlocked_achievements`, `created_at` |
| `AuthResponse` | struct | `access_token`, `refresh_token`, `user`, `is_new_user` |
| `UpdateProfilePayload` | struct | Указатели `name`, `city`, `car_clearance`, `streak_days`, `unlocked_achievements` (частичное обновление) |

Файл `internal/models/trip.go` описывает `Trip`, `StartTripResponse` и `FinishTripPayload`: старт поездки, финиш с пробегом, числом дефектов и долями качества покрытия.

### internal/osrm/client.go

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `Client` | struct | `baseURL`, `http.Client` с таймаутом 5 с и предохранитель `breaker` |
| `NewClient(baseURL)` | func | Нормализует хвостовой `/` |
| `breaker` | struct | После 5 подряд сбоев (сеть, 5xx, 429) отключает OSRM на 30 с, чтобы приём телеметрии не ждал таймаут; `400 NoSegment/NoMatch` сбоем не считается |
| `Nearest(ctx, lat, lon, heading)` | method → `Snap{Lat, Lon, Name}` | `/nearest/v1/driving/{lon},{lat}`; с курсом сначала `bearings=курс,45` (сегмент по направлению движения), затем без него; привязывает, только если дорога ближе 40 м, иначе и при любой ошибке возвращает исходные координаты (fail open). `Name` — название дороги |
| `Match(ctx, trajectory)` | method → `(wkt, geomType, roadName, ok)` | `/match/v1/driving/...` с `radiuses=25` и строго возрастающими `timestamps`; из нескольких сегментов берёт самый длинный; результат — всегда `LINESTRING`; название дороги — самое частое среди `tracepoints` |

### internal/service/telemetry.go

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `MinSpeedKMH`, `BaseSpeedKMH` | const `20.0` | Нижний порог скорости и база нормализации силы |
| `ClusterEpsMeters` | const `12.0` | Радиус `ST_ClusterDBSCAN` в метрах (проекция 3857 с поправкой на широту). При `minpoints = 1` это single-linkage: большой радиус сливал соседние ямы в цепочку |
| `BumpBaseThresholdMs2`, `BumpSpeedFactor`, `RoughRmsThresholdMs2`, `RoughForceScale`, `SeverityMediumRatio`, `SeverityHardRatio` | const | Шкала серьёзности: сила удара делится на порог обнаружения для этой скорости (дублирует `constants.dart`/`detection.dart` клиента) |
| `DedupRadiusMeters`, `DedupWindowMinutes` | const `15`, `120` | Повторный проезд той же ямы тем же пользователем в этом радиусе и окне новую запись не создаёт |
| `ClusterMaxAgeDays` | const `180` | Старше этого срока точки не кластеризуются |
| `ClusterCacheTTL` | const `15 с` | Время жизни кэша ответа `GET /telemetry` |
| `RoughClusterIDOffset` | const `100000000` | Смещение `cluster_id` для `rough_road` |
| `MaxSpeedKMH`, `MaxBumpForce`, `MaxTrajectoryPoints`, `MaxDistanceBatchMeters`, `MaxCommentRunes`, `MaxClientEventIDLen` | const | Границы валидации входа |
| `ErrInvalidTelemetry`, `ErrInvalidDistance`, `ErrInvalidComment` | error | Handler отдаёт по ним `400` |
| `ValidatePayload(p)` | func | Диапазоны координат, скорости и силы, whitelist `defect_type`, длина трека и `client_event_id` |
| `TelemetryService` | struct | Пул `pgx`, OSRM-клиент и кэш кластеров |
| `CalculateNormalizedForce(bumpForce, speedKMH)` | method → `float64` | `force × 20 / max(speed, 20)` |
| `ResolveLocation(ctx, payload)` | method → `(wkt, geomType, roadName)` | `rough_road` с треком длиннее 2 точек → `/match` (`LINESTRING`); всё остальное → `/nearest` от координат события с учётом `heading_deg` (`POINT`). Трек для ям не используется |
| `SeverityFor(defectType, rawForce, speedKMH)` | func → `1..3` | Ровно / заметно / жёстко по превышению порога обнаружения, не зависит от скорости |
| `SaveTelemetry(ctx, payload)` | method → `*TelemetryResponse` | Дефолты `pothole`/`road`, валидация, привязка к дороге, поиск дубля (`duplicate: true`, запись не создаётся), `INSERT ... ON CONFLICT (user_id, client_event_id)`: повтор возвращает уже сохранённую строку. `timestamp` берётся из `event_time_ms`, если он в окне −48 ч … +5 мин, иначе `NOW()`; исходная сила — в `raw_bump_force`, оценка — в `severity`, дорога — в `road_name` |
| `GetClusters(ctx)` | method → `[]TelemetryCluster` | Кэш на 15 с (при ошибке БД отдаётся устаревший). Два запроса по общему `clusterSQL`: ямы и линии `rough_road`; для линий — `lines` (каждая линия отдельно) и `coordinates` (одной ломаной, для старых клиентов). `severity` — p75 при трёх и более ударах, `road_name` — самое частое |
| `RecordDistance(ctx, userID, meters)` | method → `*DistanceResponse` | Потолок `5000` м на запрос; атомарный `UPDATE users SET total_distance_meters = ... RETURNING`; для пустого `userID` и `anonymous` запись пропускается, итог нулевой; удалённый пользователь → `ErrUserNotFound` |
| `AddComment(ctx, clusterID, userID, authorName, text)` | method → `*DefectComment` | Имя автора берётся из `users`, параметр `authorName` игнорируется; текст до 1000 символов |
| `GetComments(ctx, clusterID)` | method → `[]DefectComment` | Комментарии кластера, новые сверху |

**Правило подтверждения кластера:** `unique_users >= 2` **или** три разных пары «пользователь-день» (считается в SQL и в Go). Записи `anonymous` (гости, удалённые аккаунты) «водителями» не считаются и идут только в `total_hits`. Три удара одного человека за одну поездку дефект не подтверждают, как и повторные проезды в течение 2 часов. Серьёзность кластера — p75 при трёх и более ударах, иначе максимум.

### internal/service/auth.go

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `ErrInvalidCode`, `ErrCodeExpired`, `ErrTooManyAttempts`, `ErrRateLimited`, `ErrOTPLocked`, `ErrInvalidPhone`, `ErrInvalidProfile`, `ErrInvalidToken`, `ErrUserNotFound` | error | Типизированные ошибки; `respondError` в handler мапит их в коды |
| `MaxStreakDays`, `MaxAchievements` | const `3650`, `30` | Потолки значений из `sync-stats`: они входят в рейтинг, но приходят с клиента |
| `AuthService` | struct | Пул `pgx`, `jwtSecret` и `sms.Provider` |
| `NewAuthService(pool, secret, smsProvider)` | func | При `nil` подставляется `sms.NewMockProvider()`; секрет короче 32 символов даёт предупреждение |
| `RequestCode(ctx, rawPhone)` | method → `(retryAfter, error)` | 4-значный код, в `otp_codes` лежит HMAC (секрет + номер), TTL 5 мин. Окно повтора (60 с, а после трёх неверных попыток — 15 мин) проверяется атомарно в UPSERT. Код наружу не возвращается |
| `VerifyCode(ctx, rawPhone, code)` | method → `*AuthResponse` | Попытка списывается одним `UPDATE` до сравнения (не более 3), TTL и `hmac.Equal`; пользователь создаётся через `INSERT ... ON CONFLICT (phone)`; access (HS256, 24 ч) и refresh (32 байта hex, sha256 в БД, 60 дней) |
| `Refresh(ctx, oldToken)` | method → `*AuthResponse` | Условный `UPDATE ... SET revoked` атомарно отзывает старый refresh, один токен нельзя обменять дважды; отозванные токены хранятся ещё 7 дней |
| `Logout(ctx, token)` | method → `error` | Отзыв refresh-токена |
| `ValidateAccessToken(tokenStr)` | method → `(userID, error)` | Только HS256, обязательный `exp`, извлечение `sub` |
| `GetProfile(ctx, userID)` | method → `*UserProfile` | `getUser` плюс `COUNT(*)` дефектов, рейтинг по четырём слагаемым, «подвесок спасено» и `PERCENT_RANK()` |
| `UpdateProfile(ctx, userID, payload)` | method → `*UserProfile` | Частичный `UPDATE ... COALESCE`; имя и город до 100 символов, клиренс 0–600 |
| `SyncStats(ctx, userID, streak, achievements)` | method → `*UserProfile` | Записывает серию и награды с ограничением по `Max*` и возвращает профиль |
| `DeleteAccount(ctx, userID)` | method → `error` | Транзакция: анонимизация телеметрии и удаление пользователя |
| `getUser`, `normalizePhone`, `hashString`, `hashOTP`, `generateAccessToken`, `generateRefreshToken` | private | Чтение строки `users`, нормализация номера (только цифры, `8…` → `+7…`), sha256, HMAC кода, выпуск токенов |

Определение «нового» пользователя: пустые имя **или** город.

### internal/handler/

| Файл | Сущность | Тип | Назначение |
|------|----------|-----|------------|
| `http.go` | `respondJSON`, `respondDetail`, `respondError` | funcs | Единый формат ответа и маппинг ошибок сервисов: `400` валидация, `401` код/токен/пользователь, `429` лимиты, остальное — `500` с общим текстом (детали только в лог) |
| `http.go` | `decodeJSON`, `userIDFrom` | funcs | Разбор тела с лимитом 256 КБ и `user_id` из контекста |
| `ratelimit.go` | `RateLimiter` / `NewRateLimiter(limit, window)` | struct / func | Скользящее окно в памяти процесса, `Allow(key)` |
| `ratelimit.go` | `RateLimit(l, trustProxy)` | func → middleware | Ключ — пользователь из JWT, для гостей IP; при отказе `429` и `Retry-After` |
| `telemetry.go` | `PostTelemetry` | method | Разбор JSON, порог `MinSpeedKMH` (400 `Speed too low`), `user_id` из контекста или `anonymous`; присланный, но невалидный токен → `401` (иначе яма записалась бы гостем и дала ложное подтверждение; клиент обновляет токен и повторяет) |
| `telemetry.go` | `GetTelemetry`, `PostDistance` | methods | Кластеры; пробег: невалидный токен → `401` (иначе клиент считал бы гостевой `200` успехом и стирал буфер) |
| `telemetry.go` | `GetComments` / `PostComment` | methods | Чтение по `cluster_id` и добавление (автор — из профиля пользователя в БД) |
| `trip.go` | `StartTrip`, `FinishTrip`, `GetLastTrip` | methods | Старт, финиш с агрегатами и последняя поездка (`404` для чужой или уже завершённой, `400` для невалидных значений; лимит 30 в минуту) |
| `auth.go` | `RequestCode`, `VerifyCode`, `Refresh`, `Logout`, `GetMe`, `UpdateMe`, `DeleteMe`, `SyncStats` | methods | Валидация payload, ответы через `respondError` |
| `middleware.go` | `ContextUserIDKey` | const `contextKey` | Ключ `user_id` в `context.Context` |
| `middleware.go` | `RequireAuth(authService)` | func → `func(http.Handler) http.Handler` | Обязательный `Authorization: Bearer`, иначе `401` |
| `middleware.go` | `OptionalAuth(authService)` | func → `func(http.Handler) http.Handler` | Пробрасывает `userID`, если токен валиден; гостевые запросы не блокирует |

### Dockerfile и docker-compose.yaml

- **Dockerfile**: сборка `CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /app/server cmd/api/main.go`, рантайм `alpine` с `ca-certificates` и `tzdata`, порт 8000. Базовый образ сборки — `golang:1.25-alpine`, как и требует `go.mod`.
- **Compose**: `db` (`postgis/postgis:15-3.3`, том `road_pulse_data`, БД `road_pulse_db`) и `api` (сборка из Dockerfile, порт `8001:8000`, ENV `DATABASE_URL`, `PORT`, `OSRM_BASE`, `JWT_SECRET`).

## 📱 Клиент

Дизайн-система «Полотно»: две темы (светлая «бетон» и тёмная «асфальт»), шрифты Unbounded (заголовки и цифры), Onest (интерфейс), JetBrains Mono (телеметрия) — из `assets/fonts/`.

```
lib/
├── main.dart                     # entry, MyApp, themeModeNotifier, AuthGate
├── app_theme.dart                # PolotnoColors (ThemeExtension), context.colors, AppTheme
├── constants.dart                # единые пороги: скорость, степени, одометр, батчи
├── calculations.dart             # чистые функции: рейтинг, бейдж, шаг, даты, фильтры
├── fresh_prefs.dart              # SharedPreferences с принудительным reload()
├── gps.dart                      # gpsStreamSettings: фикс раз в 1 с на Android, режим навигации на iOS
├── address_service.dart          # название места дефекта: сервер (road_name) → геокодер, кэш
├── detection.dart                # bumpThresholdFor(скорость), GravityFilter (вертикаль и горизонталь)
├── theme_store.dart              # ThemeStore: сохранение режима темы
├── main_scaffold.dart            # shell + bottom nav: Карта / Дефекты / Запись / Профиль
├── map_screen.dart               # карта кластеров и линий + капсула + шторка маршрута
├── list_screen.dart              # лента дефектов: сводка с Полосой, фильтры, карточки
├── detect_screen.dart            # экран «Запись»: спидометр, пробег поездки, журнал, служба
├── pothole_details_screen.dart   # карточка дефекта: данные кластера и комментарии из API
├── profile_screen.dart           # профиль: статы с сервера, бейдж, поездка, достижения
├── achievement_service.dart      # каталог 30 достижений, локальный прогресс и пробег
├── api_service.dart              # HTTP, токены, логи, статистика, поездки, комментарии
├── sensor_service.dart           # background TaskHandler: акселерометр, трек, одометр
├── screens/
│   ├── auth_screen.dart          # флоу входа: старт → номер → код → имя → доступы
│   └── account_screen.dart       # аккаунт: профиль, доступы, выход, удаление
└── widgets/
    ├── glass_panel.dart          # стеклянный контейнер (цвета темы)
    ├── onboarding_panel.dart     # запрос доступов перед первым стартом службы
    ├── theme_mode_selector.dart  # переключатель «Система / Светлая / Тёмная»
    ├── road_ribbon.dart          # «Полоса» — лента качества покрытия
    ├── nav_arrow.dart            # «вы здесь»: навигационная стрелка по курсу, без курса — точка
    └── defect_address.dart       # подпись места дефекта (дорога с сервера, запасной геокодер)
```

### main.dart

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `themeModeNotifier` | `ValueNotifier<ThemeMode>` | Глобальное переключение темы; стартовое значение читается из `ThemeStore`, каждое изменение сохраняется |
| `main()` | entry | `ensureInitialized`, `initCommunicationPort`, загрузка темы, `ApiService.recordAppOpen()`, `runApp` |
| `MyApp` | StatelessWidget | `MaterialApp`: светлая и тёмная темы + `themeModeNotifier`, home — `AuthGate` |
| `AuthGate` | StatefulWidget | Состояние `bool? _authenticated` по `ApiService.isAuthenticated()`: ожидание → спиннер, авторизован → `MainScaffold`, иначе `AuthScreen`. На `AppLifecycleState.resumed` фиксирует вход в статистику активности и перепроверяет сессию (фоновая служба могла сбросить её из-за отозванного refresh), не перерисовывая интерфейс спиннером |

### app_theme.dart

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `PolotnoColors` | `ThemeExtension<PolotnoColors>` | Токены: `voidBg`, `asphalt`, `surf`/`surf2`, `edge`/`edge2`, `ink`/`ink2`/`ink3`, `mark*`, `s1`/`s2`/`s3` (+ `Soft`), `glass`, `glassTab`, `term`; пресеты `light` (`#EDEDEA`) и `dark` (`#08090A`) |
| `PolotnoThemeContext.colors` | extension on `BuildContext` | Доступ к токенам текущей темы |
| `AppTheme` | class | `fontUi = 'Onest'`, `fontDisplay = 'Unbounded'`, `fontMono = 'JetBrains Mono'`, `lightTheme`/`darkTheme` (Material 3) |

### main_scaffold.dart

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `MainScaffold` | StatefulWidget | `IndexedStack` из `MapScreen` / `ListScreen` / `DetectScreen` / `ProfileScreen` + стеклянный таб-бар на 4 таба |
| `MainScaffold.of(context)` | static | Доступ к состоянию из потомков |
| `MainScaffoldState.switchTab(index)` | method | Переключение вкладки (используется картой для переходов) |

### map_screen.dart

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `MapScreen` | StatefulWidget | `onNavigateToTab` — колбэк перехода на другую вкладку |
| `_applyPosition` / `_locateUser` / `_loadBumps` | private methods | Позиция, скорость и курс (скорость ≥ 1.5 м/с, накопленный угол без обнуления на 360°) и `ApiService.getBumps()`; маркер «вы здесь» — `NavArrow` |
| `_buildCircles` / `_buildPolylines` | methods | Подтверждённые кластеры: ореол и ядро, радиус и цвет по `severity` (`defectSeverity`); линии `rough_road` рисуются отдельными `Polyline` по `lines` |
| `_buildMarkers` | method | Неподтверждённые кластеры — полые серые кружки |
| `_buildRecordCapsule` / `_buildSearchBar` / `_buildFloatingActionBtn` | methods | Верхние оверлеи карты (капсула «ЗАПИСЬ», поиск «Куда едем?», кнопки «где я» и слои) |
| `_buildDraggableSheet` | method | `DraggableScrollableSheet` (`0.22`/`0.38`/`0.85`): Полоса по долям `severity` реальных дефектов, стат-пилюли (один `Future<UserStats>` в состоянии, а не запрос на каждую перерисовку) и «Ближайшие дефекты» по расстоянию до пользователя |

Тайлы: `tile.openstreetmap.org`, в тёмной теме — `darkModeTileBuilder`.

### list_screen.dart

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `ListScreen` | StatefulWidget | Лента: сводка (всего и подтверждено + Полоса по `max_force`) и карточки дефектов |
| `_filters` / `_applyFilter` | field / method | Чипы «Сегодня / Неделя / Месяц / Всё время» и сортировка по дате |
| `_parseDate` | method | `created_at` → `timestamp` → `DateTime.now()`: API дату не отдаёт, поэтому фильтры работают как заготовка |
| `DefectAddress` | widget | Подпись места: `road_name` сервера сразу, иначе геокодер через `AddressService` (кэш по координатам); запасных значений «Москва/Улица» нет |
| `_buildDefectCard` | method | Плейсхолдер-превью с бейджем S/M/L, подпись места, координаты, дата и время, `severity` → РОВНО/ЗАМЕТНО/ЖЁСТКО, счётчик подтверждений, «Объезд», переход в `PotholeDetailsScreen` |
| `_buildEmptyState` / `RefreshIndicator` | widgets | Пустое состояние и обновление жестом |

### detect_screen.dart

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `DetectScreen` | StatefulWidget | Экран «Запись»: реальные GPS и акселерометр, счётчик пробега поездки, старт и остановка foreground-службы; дерево обёрнуто в `WithForegroundTask` |
| `_tripDistanceMeters` / `_lastPos` | fields | Пробег поездки (приходит сообщением `TRIP:<метры>` из isolate) и последняя позиция для спидометра |
| `_checkPermissionsAndStart` | method | Автостарт при выданном доступе, иначе пуш `OnboardingPanel` |
| `_initForegroundTask` | method | `FlutterForegroundTask.init`: канал `road_pulse_tracking` («Road Pulse Tracking»), `eventAction.repeat(5000)`, wake/wifi lock |
| `_toggleTracking` | method | `startService(callback: startCallback)` / `stopService`; при старте обнуляет счётчик поездки, метры при этом считает isolate |
| `_onReceiveTaskData` | method | Логи и сообщения `TRIP:<метры>` из isolate → `ApiService.addLog` и счётчик поездки |
| `_initSensors` | method | Стрим позиции (`distanceFilter: 1`) для спидометра и стрим `accelerometer` (10 мс, тот же период, что в isolate) через `GravityFilter`; пик за интервал перерисовки (~15 кадров/с) попадает в осциллограф; одометром экран не владеет |
| `_buildOdometerCard` | method | Карточка «ПРОБЕГ ЗА ПОЕЗДКУ» под спидометром: километры и метры в реальном времени |
| `_buildSpeedometer` / `_buildGateBanner` | methods | Крупная скорость и баннер: пробег пишется на любой скорости, удары — от 20 км/ч |
| `_buildScope` / `PolotnoScopePainter` | widget / CustomPainter | Осциллограф вертикальной составляющей, м/с²; пунктирный порог — `bumpThresholdFor(скорость)` (`_drawDashedLine`) |
| `_buildTerminal` | method | Журнал событий из `ApiService.logs` (последние 6 строк, классификация по префиксам) |

### profile_screen.dart

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `ProfileScreen` | StatefulWidget | Секции: заголовок с инициалами из `ApiService.getUserProfile()`, ранговый бейдж сообщества, сетка статов, Полоса последней поездки из `GET /trips/last`, достижения, теплокарта |
| `_statsFuture` / `initState` / `RefreshIndicator` | field / hooks | Один общий `Future<UserStats>` на бейдж и сетку; пересоздаётся при открытии вкладки и по pull-to-refresh после `freshPrefs()` |
| `_buildCommunityBadge` | method | `FutureBuilder<UserStats>`: текст берётся из `communityBadgeText(rating, percentile:)` |
| `_buildLastTrip` | method | `FutureBuilder<TripData?>` по `ApiService.getLastTrip()` |
| `_buildStatsGrid` | method | `FutureBuilder<UserStats>`: дефекты, километры и метры трекинга, очки рейтинга с числом наград и дней серии, «подвесок спасено» |
| `_formatNumber` / `_formatKm` | static methods | Разряды через пробел и формат километров (два знака до 100 км) |
| `_buildAchievements` / `_showAchievementsSheet` | methods | Топ-8 достижений и шит «Все 30» (`_AllAchievementsSheet`) |
| `_buildActivityHeatmap` | method | Сетка 28 дней из `ApiService.getActivityData()` (серия, входы, активные дни) |
| `_formatStreak` / `_formatVisits` | static methods | Русские формы числительных |

### pothole_details_screen.dart

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `PotholeDetailsScreen` | StatefulWidget | Карточка дефекта: принимает `defect` (кластер из API), показывает силу, тип, счётчики, правило подтверждения, мини-карту и комментарии из API; фото — плейсхолдеры |
| `_lat` / `_lon` / `_clusterId` | getters | Достают координаты и `cluster_id` из `defect`, без мок-значений |
| `_resolveAddress` | method | Название места через `AddressService.resolve` (дорога с сервера или геокодер) |
| `_commentsFuture` / `_reloadComments` | field / method | Загрузка комментариев через `ApiService.getComments` |
| `ImpactSpikePainter` | CustomPainter | График профиля удара |
| `MiniRoadPainter` | CustomPainter | Схематичная мини-карта |

Кластер передаётся параметром: и карта, и лента открывают экран с данными дефекта.

### achievement_service.dart

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `Achievement` | class | `id`, `category`, `title`, `description`, `icon`, `current`, `target`, `isUnlocked`, `progressRatio` |
| `AchievementService.categories` | const list | «Все», «Старт», «Водитель», «Житель», «Порядочный гражданин», «Моя яма», «Доверие и сообщество» |
| `getAchievements()` | static Future | Каталог 30 достижений и прогресс из `SharedPreferences` (серия дней подтягивается из активности) |
| `getTotalDistanceMeters()` / `getTotalDistanceKm()` | static Future | Накопленный пробег из `SharedPreferences` |
| `addDistanceMeters(meters)` | static Future | Накопление километража, зачёт `first_km` и `thousand` |
| `syncDefectsProgress(count)` | static Future | Синхронизация `first_find`, `sharp_eye`, `road_scanner` по числу зачтённых дефектов |
| `checkCarProfile({model, tires, clearance})` | static Future | Зачёт `car_profile` |
| `increment(id, [delta])` | static Future | Инкремент произвольной записи прогресса |
| `_catalog`, `_loadRawProgress`, `_saveRawProgress` | private | Каталог и хранилище (стартовые значения для `first_km`, `first_find`, `sharp_eye`, `thousand`) |

### api_service.dart

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `ApiService` | class (static) | Единая точка HTTP, токенов, логов, статистики, поездок и комментариев |
| `baseUrl` / `apiUrl` | const | Адрес API из `String.fromEnvironment('API_BASE_URL')` с прод-дефолтом |
| `logs` | `ValueNotifier<List<LogEntry>>` | Буфер журнала для экрана «Запись» |
| `addLog(raw)` | static | Чистит эмодзи-префиксы isolate и классифицирует запись в `LogKind.ok`/`hit`/`warn` |
| `LogEntry` / `LogKind` | class / enum | Строка журнала: время, текст, вид |
| `VerifyResult` | class | `success`, `isNewUser`, `errorMessage` |
| `DayActivity` / `UserActivityData` | class | Ячейка теплокарты (уровни 0–3) и агрегат за 28 дней (серия, входы, активные дни) |
| `recordAppOpen()` / `getActivityData()` | static Future | Учёт входов в `SharedPreferences` (хранение 90 дней) и сборка сетки 28 дней |
| `requestCode(phone)` / `verifyCode(phone, code)` | static Future | Авторизация; сохранение access/refresh токенов и профиля |
| `updateProfile({name, city, clearance})` | static Future | Локальное сохранение и `PATCH /auth/me` при наличии токена |
| `deleteAccount()` | static Future | `DELETE /auth/me` с последующей очисткой локальной сессии |
| `getAccessToken()` / `getValidAccessToken()` | static Future | Access-токен с автообновлением: за 60 с до `exp` меняется по refresh (`refreshTokens`, один запрос на изолят, защита от гонки между изолятами) |
| `isAuthenticated()` / `getUserProfile()` / `logout()` | static Future | Работа с сессией (токены и профиль в `SharedPreferences`) |
| `_httpTimeout` | const `12 с` | Таймаут каждого HTTP-вызова; зависший запрос иначе блокировал бы отправку пробега |
| `UserStats` | class | DTO профиля: `totalKm`, `totalDefects`, `rating`, `savedSuspensions`, `unlockedAchievements`, `streakDays`, `communityPercentile` (+ `empty()`) |
| `getDefectsCount()` / `incrementDefectsCount([delta])` | static Future | Локальный счётчик зачтённых дефектов (`user_defects_count`) и синхронизация достижений |
| `getUserStats()` | static Future | Синхронизирует серию и награды через `POST /auth/sync-stats` (в ответе профиль со статистикой) и прибавляет неотправленный буфер; при недоступности сервера падает на локальные счётчики и `ratingFor` |
| `sendDistance(meters)` | static Future\<bool\> | `POST /api/v1/telemetry/distance`; успех — только `200` с `total_distance_meters > 0` (для гостя сервер отвечает `200` с нулём и ничего не пишет); без токена возвращает `false`, и метры остаются в буфере |
| `flushPendingDistance()` | static Future | Досылает накопленный `pending_distance_meters` после входа в аккаунт |
| `sendDefectStatus({...})` | static Future\<DefectSendResult\> | `POST /api/v1/telemetry` с `Bearer`; без токена не отправляет и возвращает 401 (событие остаётся в очереди до входа). Принимает `defectType`, `infrastructureType`, `trajectory`, `eventTimeMs`, `clientEventId`, `headingDeg`, `accuracyM`; возвращает HTTP-статус (`0` — сеть) и `duplicate`. Счётчик дефектов растёт **только** при `200` без `duplicate` |
| `startTrip()` / `finishTrip({...})` / `getLastTrip()` | static Future | `POST /trips/start`, `POST /trips/finish`, `GET /trips/last` |
| `TripData` | class | Поездка: `id`, `startedAt`, `endedAt`, `distanceMeters`, `defectsCount`, доли качества покрытия |
| `getComments(clusterId)` / `addComment({clusterId, text})` | static Future | `GET` и `POST /api/v1/telemetry/comments` |
| `DefectComment` | class | Комментарий: `id`, `clusterId`, `authorName`, `text`, `createdAt` |
| `getBumps()` | static Future\<List\<Map\>\> | `GET /api/v1/telemetry` |

`user_id` в теле POST не отправляется — сервис берёт его из JWT или помечает запись как `anonymous`.

### detection.dart и theme_store.dart

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `bumpThresholdFor(speedKmh)` | func | Порог вертикального удара: `max(kBumpBaseThresholdMs2, kBumpSpeedFactor × км/ч)`, м/с². Единственное место формулы: её используют детектор и осциллограф |
| `GravityFilter` | class | ФНЧ гравитации (τ = 0.8 с, обновляется только при ускорении около 1 g); `update(x, y, z, nowUs)` → вертикаль и горизонталь относительно гравитации, не зависит от положения телефона |
| `ThemeStore.load()` / `save(mode)` | static Future | Режим темы в `SharedPreferences` (`kKeyThemeMode`) |

### sensor_service.dart

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `startCallback()` | entry-point (`@pragma('vm:entry-point')`) | Регистрация `SensorTaskHandler` в isolate foreground-задачи |
| `TrajectoryPoint` | class | Точка трека (`lat`, `lon`, `timestamp`) и `toJson()` |
| `SensorTaskHandler` | `TaskHandler` | Фоновый isolate: позиция (`bestForNavigation`, `distanceFilter: 1`), акселерометр 100 Гц, гироскоп 50 Гц; подписки ставятся до сетевых вызовов |
| `_onPosition(p)` | method | Сохраняет фикс с его собственным временем (`wallMs`), историю из 6 фиксов, историю скорости (10 с) и буфер трека (10 точек, точность ≤ 50 м). Подписка — `gpsStreamSettings()` |
| `_positionAt(peakWallMs)` / `_courseAt(i)` | methods | Позиция на момент пика: между двумя фиксами интерполяция, после последнего — экстраполяция по курсу (до 2.5 с); курс — по смещению между фиксами, на малом шаге по `heading` |
| `_onAccel(e)` | method | `GravityFilter` → вертикаль и горизонталь; первые 2 с — прогрев |
| `_processSample(t, v, h)` | method | Запуск окна 600 мс, когда вертикаль выше `bumpThresholdFor(скорость)` (на плохой дороге порог ×1.5); нужен свежий фикс (≤ 3 с, точность ≤ 40 м, скорость ≥ 20 км/ч) |
| `_classifyWindow` / `_pulseWidthMs` | methods | Отсев: горизонталь больше вертикали (торможение, манёвр), вращение гироскопа > 5 рад/с, лежачий полицейский — один импульс шире `kSpeedBumpPulseM` метров пути (на подъезде с торможением — `kBrakedPulseM`). Ширина считается по одному импульсу в метрах, а не по времени: два удара осей ямы на малой скорости раньше выглядели как бугор. Принятое событие — пик окна |
| `_feedRoughBins` / `_evaluateRoughRoad` | methods | RMS вертикали в бинах по 0.5 с; `rough_road`, если 4 из 5 бинов выше 1.5 м/с² при 20–60 км/ч; пауза 10 с после отправки |
| `_emitDefect` / `_deliver` | methods | Серьёзность — по превышению порога (`potholeSeverity`); отправка через `ApiService.sendDefectStatus` с `clientEventId`, временем пика, курсом и точностью. Дефект идёт в счётчик поездки только после доставки и если сервер не вернул `duplicate` |
| `_queue` / `_flushQueue` | field / method | Очередь неотправленных дефектов в `SharedPreferences` (до 100, 24 ч, 5 попыток); отсутствие сети (статус 0) попыткой не считается; `4xx`, кроме 401/408/429, из очереди отбрасываются |
| `_updateDistance(position)` | method | Одометр: точность ≤ 80 м, шаг 0.6–300 м на любой скорости; опорная точка не сдвигается на микрошагах; метры идут в `AchievementService` и в буфер |
| `_checkAndSyncDistance({force})` | method | Отправка при ≥ 25 м, либо ≥ 5 м за 20 с, либо принудительно; один запрос в полёте, после ошибки пауза 15 с |
| `onStart` / `onRepeatEvent` / `onDestroy` | overrides | Старт датчиков, раз в 5 с: сохранение буфера, отправка пробега, очередь; в конце — закрытие поездки (доли качества по сегментам 100 м), сброс пробега |

### screens/auth_screen.dart

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `AuthStep` | enum | `start`, `phone`, `code`, `codeError`, `name`, `access` |
| `AuthScreen` | StatefulWidget | Пошаговый вход через `switch (_step)` в `build` |
| `_handleRequestCode` | method | `ApiService.requestCode`, таймер повторной отправки 60 с |
| `_handleVerifyCode` | method | `ApiService.verifyCode`; новый пользователь → шаг `name`, существующий → `MainScaffold`; ошибка → `codeError` |
| `_handleSaveProfileAndContinue` | method | Валидация имени и города, `ApiService.updateProfile`, переход к `access` |
| `_onKeyPress` / `_buildKeypad` | methods | Своя цифровая клавиатура для шагов «номер» и «код» |
| `_formatPhone` | method | Маска `(###) ###-##-##` при префиксе `+7` |
| `_buildStartStep` / `_buildPhoneStep` / `_buildCodeStep` / `_buildNameStep` / `_buildAccessStep` | methods | Экраны шагов: оффер, номер, 4 ячейки кода, имя/город/клиренс, список доступов |

### screens/account_screen.dart

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `AccountScreen` | StatefulWidget | Секции «ВХОД», «ВНЕШНИЙ ВИД» (`ThemeModeSelector`), «ЗАПИСЬ», «ОПАСНАЯ ЗОНА» и строка версии |
| `_loadAppVersion` | method | `PackageInfo.fromPlatform()` → «Дорожный пульс {версия} · сборка {номер}»; при ошибке — резервная строка из кода |
| `_loadProfile` | method | `ApiService.getUserProfile()` и марка/шины из `SharedPreferences` |
| `_showEditProfileDialog` | method | Диалог: имя, город, марка и модель, шины, клиренс; сохранение локально, зачёт `car_profile`, `PATCH /auth/me` |
| `_handleLogout` | method | `ApiService.logout()` → `AuthScreen` (используется и для «Удалить аккаунт») |
| `_buildGroupCard` / `_buildRowItem` / `_buildSectionHeader` | methods | Карточки-группы настроек |

### widgets/

| Сущность | Тип | Назначение |
|----------|-----|------------|
| `glass_panel.dart` → `GlassPanel` | widget | Blur и полупрозрачный `surf` с рамкой `edge`; параметры `blur`, `opacity`, `borderRadius`, `padding` |
| `onboarding_panel.dart` → `OnboardingPanel` | widget | Экран запроса доступов перед первым стартом службы (`onAllow`), анимация fade/slide, «магнитная» кнопка `_MagneticAllowButton` |
| `theme_mode_selector.dart` → `ThemeModeSelector` | widget | Сегментированный переключатель «Система / Светлая / Тёмная»: пишет в `themeModeNotifier`, цвета только из `context.colors` |
| `road_ribbon.dart` → `RoadRibbon` / `RibbonSegment` | widget / class | Лента качества из сегментов (`flex`, `color`) с маркером «вы здесь» (`currentPosition`) |

## 🔄 Потоки данных

### Запись ямы

1. `SensorTaskHandler.onStart` → стримы позиции, акселерометра и гироскопа.
2. `GravityFilter` даёт вертикаль; выше `bumpThresholdFor(скорость)` открывается окно 600 мс.
3. `_classifyWindow` отсекает торможение, лежачие полицейские (по ширине импульса в метрах) и вращение; позиция события — на момент пика (интерполяция между фиксами), курс — по движению. `rough_road` определяется отдельно по RMS, в трек уходят только последние ~5 с.
4. `ApiService.sendDefectStatus(...)` → `POST /api/v1/telemetry` с `Bearer`, если есть сессия; при сбое событие уходит в очередь.
5. Сервис: валидация → `ResolveLocation` (OSRM, с курсом) → поиск дубля (тот же пользователь, 15 м, 2 ч) → `CalculateNormalizedForce` и `SeverityFor` → идемпотентный `INSERT` в PostGIS.
6. `ApiService.sendDefectStatus` увеличивает локальный счётчик только при `200` без `duplicate`.

### Одометр и статистика

1. Владелец одометра — фоновый isolate (`sensor_service`): точность ≤ 80 м, длина шага 0.6–300 м, ограничения по скорости нет. Экран «Запись» метры не считает, а получает счётчик поездки сообщением `TRIP:<метры>`.
2. Каждый шаг идёт в локальный счётчик `AchievementService.addDistanceMeters` и в буфер отправки, который персистится в `pending_distance_meters`.
3. Буфер уходит пачками: при ≥ 25 м либо ≥ 5 м за 20 с, плюс принудительно при остановке службы. Транспорт — `ApiService.sendDistance` → `POST /api/v1/telemetry/distance`; без токена метры остаются в буфере и уходят после входа (`flushPendingDistance`).
4. Сервис атомарно прибавляет метры к `users.total_distance_meters`; для `anonymous` он только отвечает `200`, ничего не записывая.
5. Зачтённые дефекты считает клиент: `ApiService.sendDefect` увеличивает локальный счётчик **только** при ответе `200`.
6. `ProfileScreen` синхронизирует серию и награды через `POST /auth/sync-stats`, читает статистику из ответа (пробег, дефекты, рейтинг, процентиль) и прибавляет неотправленный буфер. Рейтинг и бейдж считаются на сервере; локальные формулы в `calculations.dart` используются как оффлайн-фолбэк.

### Чтение карты и ленты

1. `MapScreen._loadBumps` / `ListScreen._loadBumps` → `ApiService.getBumps()`.
2. `GET /api/v1/telemetry` → кластеры `pothole` и кластеры линий `rough_road` с `created_at` и `coordinates`.
3. Карта: `is_confirmed` → цветной `CircleMarker` (цвет и радиус по `max_force`), иначе полый `Marker`; линии рисуются `PolylineLayer` из `coordinates`.
4. Лента: карточка с адресом (`geocoding`), степенью по `max_force`, счётчиком подтверждений и фильтром периода по `created_at`.

### Комментарии к дефекту

1. `PotholeDetailsScreen` получает `defect` (кластер из API) и берёт `cluster_id`.
2. `ApiService.getComments(clusterId)` → `GET /api/v1/telemetry/comments`; отправка — `ApiService.addComment` → `POST` под `RequireAuth`.
3. Комментарии хранятся в таблице `defect_comments`; имя автора сервер берёт из профиля в БД, `author_name` из тела запроса игнорируется.

### Вход

1. `AuthScreen` → `ApiService.requestCode` → код в БД (HMAC) и в SMS; в ответе кода нет, при `MockProvider` он печатается в лог сервиса.
2. `verifyCode` → `AuthResponse`; токены и профиль в `SharedPreferences`.
3. `is_new_user` → шаг заполнения профиля, иначе сразу `MainScaffold`.
4. `AuthGate` при следующем запуске видит токен и открывает `MainScaffold`; `getAccessToken()` обновляет access по refresh за минуту до истечения.

## 🚧 Границы модулей

| Слой | Должен делать | Не должен |
|------|----------------|-----------|
| `sensor_service` | Датчики, пороги, трек, одометр, вызов API | UI, тема |
| `api_service` | HTTP, токены, буфер логов | Виджеты, бизнес-пороги датчиков |
| Экраны (`*_screen`) | UI и навигация | Дублировать HTTP-логику (только через `ApiService`) |
| `handler` | HTTP: разбор запроса, коды ответов | SQL и бизнес-правила |
| `service` | Бизнес-логика: нормализация, кластеры, OTP, JWT | Формирование HTTP-ответов |
| `models` | DTO и JSON-теги | Логика и доступ к БД |
| `database` | Пул соединений и схема | HTTP и бизнес-логика |
| `osrm` | Внешний HTTP с timeout и fallback | Знание о схеме БД |
| `sms` | Отправка кода: `GateProvider` для боевой отправки, `MockProvider` для разработки | Знание о БД и HTTP-слое API |

При добавлении файла или публичной функции — обновите этот документ.
# Дорожный пульс (Road Pulse)

Crowd-sourced карта ям: телефон в машине ловит удары акселерометра, привязывает их к GPS и собирает общую карту дефектов дороги.

> Историческое имя проекта — **EasyRide**. Оно осталось в идентификаторах Android-сборки (`applicationId com.example.easyride_app`), канале foreground-уведомления (`easyride_tracking`) и текстах `onboarding_panel.dart`. Актуальное имя продукта — **Дорожный пульс / Road Pulse**.

## Боль

- Водитель не знает, где на маршруте жёсткие ямы, пока не въедет.
- У города и сервисов нет «живой» карты дефектов покрытия — только разовые обходы и жалобы.
- Навигаторы оптимизируют время и пробки, но почти не учитывают качество асфальта.

## Решение (MVP)

1. **App (Flutter)** в foreground-службе слушает `userAccelerometer`, при силе удара выше порога берёт GPS и скорость, шлёт телеметрию на backend.
2. **Backend (Go + chi)** нормализует силу удара по скорости, «прищёлкивает» точку к дороге через OSRM (`/match`, fallback `/nearest`), сохраняет геометрию в PostGIS.
3. **Кластеризация** (`ST_ClusterDBSCAN`, `eps ≈ 0.0003°`) объединяет близкие удары; кластер считается подтверждённым, если ≥2 уникальных пользователя **или** ≥3 попадания.
4. **Карта** показывает подтверждённые ямы цветными кругами (цвет по силе), неподтверждённые — полыми маркерами.
5. **Вход по номеру телефона** с OTP-кодом: сервер отдаёт JWT-пару (access 24 ч + refresh 60 дней), профиль (имя, город, клиренс) хранится в БД; телеметрия уходит с токеном, `user_id` подставляется из JWT.

## Стек

| Слой | Технологии |
|------|------------|
| Клиент | Flutter (Dart SDK `^3.12.2`), geolocator, sensors_plus, flutter_foreground_task, flutter_map, latlong2, http, shared_preferences, geocoding |
| API | Go 1.25, chi/v5, golang-jwt/v5, pgx/v5 |
| Данные | PostgreSQL + PostGIS (`postgis/postgis:15-3.3`, Docker), SQL-схема применяется на старте |
| Внешнее | OSRM public (`https://router.project-osrm.org`) — `/match` и `/nearest` |
| Карта | Тайлы OpenStreetMap (`tile.openstreetmap.org`), ночной режим штатным `darkModeTileBuilder` |

## Структура репозитория

```
road_pulse/
├── app/          # Flutter-клиент (package road_pulse)
├── backend/      # Go API: cmd/ + internal/
└── docs/
    ├── README.md         # этот файл
    ├── ARCHITECTURE.md   # дерево модулей и публичные сущности
    └── AGENTS.md         # правила для ИИ и стиль кода
```

Подробная карта файлов и функций: **[ARCHITECTURE.md](./ARCHITECTURE.md)**.  
Правила написания кода (для людей и агентов): **[AGENTS.md](./AGENTS.md)**.

## Запуск backend

Требования: Docker, Go 1.25+ (или только Docker для контейнерной сборки).

```bash
cd backend

# 1. PostGIS (и, при желании, сам API в контейнере)
docker compose up -d db        # только БД на localhost:5432
# docker compose up -d         # БД + api, API будет доступен на localhost:8001

# 2. Локальный запуск API
export DATABASE_URL="postgresql://admin:password123@localhost:5432/road_pulse_db"
export JWT_SECRET="dev_secret"
go run ./cmd/api
```

Настройки читаются из окружения (`internal/config/config.go`):

| Переменная | Значение по умолчанию | Назначение |
|------------|----------------------|------------|
| `PORT` | `8000` | Порт HTTP-сервера |
| `DATABASE_URL` | `postgresql://admin:password123@localhost:5432/easyride_db` | DSN Postgres. **Имя БД в дефолте (`easyride_db`) не совпадает с контейнером (`road_pulse_db`) — при локальном запуске задайте `DATABASE_URL` явно** |
| `OSRM_BASE` | `https://router.project-osrm.org` | База OSRM |
| `JWT_SECRET` | `easyride_super_secret_jwt_key_2026` | Ключ подписи access-токена; в compose задаётся свой |

Схема БД (`PostGIS`, таблицы `telemetry`, `users`, `otp_codes`, `refresh_tokens`) применяется автоматически при старте.

> ⚠️ Сейчас пакет моделей не собирается: `backend/internal/models/auth.go` содержит нерабочий относительный импорт и не импортирует `time`. Подробности — в разделе «Tech debt».

Проверка:

```bash
curl http://localhost:8000/health
```

Ожидается `{"status": "ok", "postgis": "3.x ..."}`; при недоступной БД — `503`.

## Запуск app

Требования: Flutter SDK, устройство/эмулятор с GPS и акселерометром (реальный телефон предпочтительнее).

```bash
cd app
flutter pub get
flutter run
```

### Важно про API URL

Базовый URL захардкожен в `app/lib/api_service.dart`:

```dart
static const String baseUrl = 'http://31.77.105.240:8001/api/v1';
static const String apiUrl = '$baseUrl/telemetry';
```

Для локальной разработки замените хост на IP машины в той же сети, что и телефон (не `localhost` с физического устройства). Cleartext HTTP разрешён в `AndroidManifest.xml` (`android:usesCleartextTraffic="true"`).

## API (кратко)

| Метод | Путь | Авторизация | Назначение |
|-------|------|-------------|------------|
| `GET` | `/health` | — | Живость API и БД, версия PostGIS |
| `POST` | `/api/v1/auth/request-code` | — | Запросить OTP-код на номер |
| `POST` | `/api/v1/auth/verify-code` | — | Проверить код, получить JWT-пару и профиль |
| `POST` | `/api/v1/auth/refresh` | — | Обменять refresh-токен на новую пару |
| `GET` | `/api/v1/auth/me` | Bearer | Текущий профиль |
| `PATCH` | `/api/v1/auth/me` | Bearer | Обновить имя / город / клиренс |
| `POST` | `/api/v1/telemetry` | опционально Bearer | Принять дефект (яму или участок плохой дороги) |
| `GET` | `/api/v1/telemetry` | — | Список кластеров ям и плохих участков |

### Авторизация

```jsonc
// POST /api/v1/auth/request-code
{ "phone": "+79991234567" }
// → 200 { "status": "code_sent", "retry_after": 60 }

// POST /api/v1/auth/verify-code
{ "phone": "+79991234567", "code": "4821" }
// → 200 { "access_token": "...", "refresh_token": "...",
//         "user": { "id", "phone", "name", "city", "car_clearance", "created_at" },
//         "is_new_user": true }
```

SMS-шлюза нет: код печатается в лог Go-сервера (`[SMS-GATEWAY MOCK]`), срок жизни — 5 минут, не более 3 попыток, повторная отправка — через 60 с. Мастер-код **`1234`** проходит всегда. Если имя или город пустые, сервер помечает пользователя как нового (`is_new_user: true`) — клиент ведёт его на шаг заполнения профиля.

### `POST /api/v1/telemetry`

**Важно:** бэкенд отклоняет запросы со скоростью `< 20 км/ч` (возвращает `400 Bad Request`).

Тело (JSON):

```json
{
  "user_id": "test_user_01",
  "latitude": 55.75,
  "longitude": 37.61,
  "speed_kmh": 40.0,
  "bump_force": 12.5,
  "defect_type": "rough_road",
  "infrastructure_type": "road",
  "trajectory": [
    {"lat": 55.7501, "lon": 37.6101, "timestamp": 1715000000.0},
    {"lat": 55.7502, "lon": 37.6105, "timestamp": 1715000005.0}
  ]
}
```

`user_id` необязателен: при валидном Bearer-токене он перезаписывается `sub` из JWT, иначе пустой заменяется на `anonymous`. `defect_type` по умолчанию `pothole`, `infrastructure_type` — `road`.

Ответ (успех): `status`, `id`, `snapped_lat`, `snapped_lon`, нормализованный `bump_force` (`force * 20 / max(speed, 20)`), `defect_type`, `infrastructure_type`, `geometry_type` (`Point` или `LineString`).

Геометрия: трек длиннее 2 точек уходит в OSRM `/match`; `rough_road` сохраняется как `LINESTRING`, `pothole` — как `POINT` (первая точка матча). Если матч не удался — `POINT` по OSRM `/nearest`.

### `GET /api/v1/telemetry`

Массив кластеров: `cluster_id`, `lat`, `lon`, `max_force`, `unique_users`, `total_hits`, `is_confirmed`, `defect_type`, `infrastructure_type`.

- `pothole` — кластеры `ST_ClusterDBSCAN` (центроид, счётчики, `is_confirmed = unique_users >= 2 || total_hits >= 3`).
- `rough_road` — каждая запись отдаётся отдельным «кластером» (`cluster_id = id + 1000000`, `unique_users = 1`, `total_hits = 1`, `is_confirmed = false`), потому что линии пока не кластеризуются.
- Дата записи в ответе **не отдаётся** (см. tech debt).

## Дизайн: «Полотно»

Приложение построено на дизайн-системе «Полотно»:

- **Две темы**: светлая «бетон» (#EDEDEA) и тёмная «асфальт» (#08090A) — не инверсия, у каждой своя палитра. Реализованы как `ThemeExtension` `PolotnoColors` (`app_theme.dart`), доступны через `context.colors`.
- **Шрифты**: Unbounded (заголовки и цифры), Onest (интерфейс), JetBrains Mono (телеметрия) — подключены локально из `app/assets/fonts/`, интернет не нужен.
- **Полоса** (`RoadRibbon`) — дорога как непрерывная лента, окрашенная по качеству: в ленте дефектов и в шторке карты; поддерживает маркер «вы здесь».
- **Степени дефектов** вместо S/M/L: **Ровно / Заметно / Жёстко**. Пороги по `max_force`: `> 30` — жёстко, `> 20` — заметно, иначе ровно. Пороги продублированы в `map_screen.dart` и `list_screen.dart` (см. tech debt).
- **Переключение темы** — глобальный `ValueNotifier<ThemeMode> themeModeNotifier` в `main.dart`; экран «Аккаунт» пока не содержит переключателя.

## Экраны приложения (обзор)

| Вкладка / место | Экран | Статус |
|---------|--------|--------|
| Вход | `AuthScreen` (`screens/auth_screen.dart`) | Серверная авторизация: номер → код → имя/город/клиренс → доступы |
| Карта | `MapScreen` | Живые данные API (круги/маркеры) + OSM-тайлы; капсула записи, поиск и шторка — макет |
| Дефекты | `ListScreen` | Живые данные API, сводка с Полосой, фильтры, реверс-геокодинг адресов |
| Запись | `DetectScreen` | Реальный foreground-скан, осциллограф с порогом 7 g, журнал событий |
| Профиль | `ProfileScreen` | Профиль из хранилища, 30 достижений (локальный прогресс), теплокарта входов |
| Аккаунт | `AccountScreen` | Профиль, редактирование, доступы, выход |
| Детали дефекта | `PotholeDetailsScreen` | Полностью статичный макет: сила, адрес, комментарии — заглушки |

## Tech debt (осознанно)

- Хардкод URL API (`31.77.105.240:8001`) в клиенте.
- Учётные данные БД и дефолтный `JWT_SECRET` в исходниках/дефолтах (MVP/dev).
- Авторизация без реального SMS-провайдера: код в логах сервера, мастер-код `1234`; выход и «удалить аккаунт» просто чистят локальные токены.
- `GET /api/v1/telemetry` не отдаёт дату записи, поэтому фильтры периодов («Сегодня / Неделя / Месяц») в ленте фактически показывают все записи.
- `rough_road` отдаётся по одной записи на строку — линии вдоль дороги не кластеризуются и не рисуются как линии.
- Пороги степеней (20/30) и порог скорости (20 км/ч) продублированы в нескольких файлах вместо общих констант.
- Макетные данные в UI: капсула записи («58 км/ч»), статистика маршрута и «Ближайшие дефекты» в шторке карты, цифры профиля, весь `PotholeDetailsScreen`, комментарии.
- Прогресс достижений хранится в `SharedPreferences` (часть значений проставлена «стартовыми»), километраж считается на клиенте.
- Сборка `app/android` всё ещё использует `com.example.easyride_app`, хотя карта представляется как `com.roadpulse.app`; строка версии в «Аккаунте» (`2.0 · сборка 16`) расходится с `pubspec.yaml` (`1.2.1+17`).
- Каркас Dockerfile собран на `golang:1.22-alpine`, тогда как `go.mod` требует Go 1.25.
- `backend/internal/models/auth.go` содержит нерабочий импорт (`../../../backend/internal/models/time`) и использует `time.Time` без импорта `time` — пакет моделей в текущем виде не компилируется.

## Для ИИ и контрибьюторов

1. Прочитай **[AGENTS.md](./AGENTS.md)** — чеклист перед каждой новой функцией.
2. Сверься с **[ARCHITECTURE.md](./ARCHITECTURE.md)**, чтобы не дублировать модули.
3. Не меняй контракт API без синхронного обновления клиента и этих документов.

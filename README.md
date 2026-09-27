# EasyRide

Crowd-sourced карта ям: телефон в машине ловит удары акселерометра, привязывает их к GPS и собирает общую карту дефектов дороги.

## Боль

- Водитель не знает, где на маршруте жёсткие ямы, пока не въедет.
- У города и сервисов нет «живой» карты дефектов покрытия — только разовые обходы и жалобы.
- Навигаторы оптимизируют время и пробки, но почти не учитывают качество асфальта.

## Решение (MVP)

1. **App (Flutter)** в foreground-службе слушает `userAccelerometer`, при силе удара выше порога берёт GPS и скорость, шлёт телеметрию на backend.
2. **Backend (FastAPI + PostGIS)** нормализует силу удара по скорости, «прищёлкивает» точку к дороге через OSRM Nearest, сохраняет `POINT` в PostGIS.
3. **Кластеризация** (`ST_ClusterDBSCAN`) объединяет близкие удары; кластер считается подтверждённым, если ≥2 уникальных пользователя **или** ≥3 попаданий.
4. **Карта** показывает подтверждённые ямы цветом по силе, неподтверждённые — серыми маркерами.

## Стек

| Слой | Технологии |
|------|------------|
| Клиент | Flutter (Dart 3), geolocator, sensors_plus, flutter_foreground_task, flutter_map, latlong2, http |
| API | FastAPI, Pydantic, Uvicorn |
| Данные | PostgreSQL + PostGIS (Docker), SQLAlchemy, GeoAlchemy2 |
| Внешнее | OSRM public `nearest` (`router.project-osrm.org`) |

## Структура репозитория

```
projects/
├── README.md                 # этот файл
├── ARCHITECTURE.md           # дерево модулей и публичные сущности
├── AGENTS.md                 # правила для ИИ и стиль кода
├── easyride_app/             # Flutter-клиент
└── easyride_backend/         # FastAPI + PostGIS
```

Подробная карта файлов и функций: **[ARCHITECTURE.md](./ARCHITECTURE.md)**.  
Правила написания кода (для людей и агентов): **[AGENTS.md](./AGENTS.md)**.

## Запуск backend

Требования: Docker, Python 3.11+.

```bash
cd easyride_backend

# PostGIS
docker compose up -d

# Зависимости (один раз)
python -m venv venv
# Windows:
venv\Scripts\activate
# Linux/macOS:
# source venv/bin/activate
pip install -r requirements.txt

# API
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Проверка:

```bash
curl http://localhost:8000/health
```

Ожидается JSON со `"status": "ok"` и версией PostGIS.

Строка подключения к БД сейчас в `easyride_backend/database.py`:

`postgresql://admin:password123@localhost:5432/easyride_db`

## Запуск app

Требования: Flutter SDK, устройство/эмулятор с GPS и акселерометром (реальный телефон предпочтительнее).

```bash
cd easyride_app
flutter pub get
flutter run
```

### Важно про API URL

Базовый URL захардкожен в `easyride_app/lib/api_service.dart`:

```dart
static const String apiUrl = 'http://31.77.105.240:8000/api/v1/telemetry';
```

Для локальной разработки замените хост на IP машины в той же сети, что и телефон (не `localhost` с физического устройства). Android cleartext HTTP может потребовать network security config.

## API (кратко)

| Метод | Путь | Назначение |
|-------|------|------------|
| `GET` | `/health` | Живость API и БД, версия PostGIS |
| `POST` | `/api/v1/telemetry` | Принять дефект (яму или участок плохой дороги) |
| `GET` | `/api/v1/telemetry` | Список кластеров ям и плохих участков |

### `POST /api/v1/telemetry`

**Важно:** Бэкенд отклоняет запросы со скоростью `< 20 км/ч` (возвращает `400 Bad Request`).

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

Ответ (успех): `status`, `id`, `snapped_lat`, `snapped_lon`, нормализованный `bump_force`, `geometry type`(`Point` или `LineString`).

### `GET /api/v1/telemetry`

Массив кластеров: `cluster_id`, `lat`, `lon`, `max_force`, `unique_users`, `total_hits`, `is_confirmed`.

## Дизайн: «Полотно»

Приложение построено на дизайн-системе «Полотно» (прототип — `polotno-2темы.html`):

- **Две темы**: светлая «бетон» и тёмная «асфальт» (не инверсия, у каждой своя шкала). Следует системной, переключается в **Профиль → Аккаунт → Тема**.
- **Шрифты**: Unbounded (заголовки и цифры), Onest (интерфейс), JetBrains Mono (телеметрия) — через `google_fonts` (нужен интернет при первом запуске, потом кэш).
- **Полоса** (Ribbon) — дорога как непрерывная лента, окрашенная по качеству: в ленте, шторке карты и профиле.
- **Степени дефектов** вместо S/M/L: **Ровно / Заметно / Жёстко**. Пороги по нормализованной силе — 3 и 5 (единое место: `defect_item.dart`). Нормализация API (`force * 20 / max(speed, 20)`) прижимает значения вниз, поэтому пороги прототипа 20/30 делали бы все дефекты «Ровно».
- **Вход моковый**: серверной авторизации ещё нет — флоу входа (старт → номер → код → знакомство → доступы) работает локально, любой 4-значный код проходит (`0000` показывает состояние ошибки). `user_id` телеметрии не менялся.

## Экраны приложения (обзор)

| Вкладка / место | Экран | Статус |
|---------|--------|--------|
| Вход | `AuthFlow` (5 экранов) | Мок-авторизация, UI по макету |
| Карта | `MapScreen` | Живые данные API + капсула записи + шторка |
| Дефекты | `ListScreen` | Живые данные API, сводка с Полосой |
| Запись | `DetectScreen` | Реальный foreground-скан, график с порогом 7 g, цветной журнал |
| Профиль | `ProfileScreen` | Мок-данные + вход в аккаунт |
| Аккаунт | `AccountScreen` | Тема, доступы, выход/удаление (мок) |
| Детали | `PotholeDetailsScreen` | Поля API (force/users/hits/confirmed) + мини-карта; фото/комментарии — мок |

## Tech debt (осознанно)

- Хардкод URL API и `user_id` в клиенте.
- Учётные данные БД в исходниках (только для MVP/dev).
- Авторизация моковая: нет `POST /auth/request-code` и `/auth/verify`, сессия живёт в памяти (после перезапуска — снова экран входа), `user_id` не привязан к аккаунту.
- Дата кластера не отдаётся API, поэтому фильтры периодов в ленте показывают все записи.
- Фото дефектов, комментарии и цифры профиля — заглушки.
- `rough_road` рисуется точкой (квадратик), а не линией вдоль дороги — для линий нужно отдавать геометрию LINESTRING в GET-ответе.

## Для ИИ и контрибьюторов

1. Прочитай **[AGENTS.md](./AGENTS.md)** — чеклист перед каждой новой функцией.
2. Сверься с **[ARCHITECTURE.md](./ARCHITECTURE.md)**, чтобы не дублировать модули.
3. Не меняй контракт API без синхронного обновления клиента и этих документов.

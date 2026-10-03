# Правила для ИИ и разработчиков (Дорожный пульс / Road Pulse)

Этот файл — обязательный контекст для любого агента (Cursor, Claude, Grok, Codex, DeepSeek и т.д.) и ориентир для человека.  
Перед правками прочитай [ARCHITECTURE.md](./ARCHITECTURE.md) и [README.md](./README.md).

---

## Роль

Ты помогаешь развивать monorepo Road Pulse (историческое имя — EasyRide):

- `app/` — Flutter-клиент (package `road_pulse`)
- `backend/` — Go API (module `road_pulse/backend`): chi + pgx + PostGIS + JWT

Пиши **чистый, короткий, масштабируемый** код. Не раздувай scope. Не «улучшай всё подряд» без запроса.

---

## Чеклист ПЕРЕД каждой новой строкой / методом / функцией

Перед тем как написать новый код, **явно** проверь:

1. **Дублирование**  
   Есть ли уже такой (или почти такой) код в `app/lib` или `backend/internal`?  
   Поищи по имени, смыслу, endpoint, виджету.  
   **Если есть — переиспользуй, вынеси общее, не копируй.**  
   Известный долг: пороги силы (`> 20` / `> 30`) и порог скорости (`20 км/ч`) продублированы в `map_screen.dart`, `list_screen.dart`, `sensor_service.dart` и `internal/service/telemetry.go`. Новый порог — только в общее место (константы сервиса/клиента), без третьей копии.

2. **Актуальность API**  
   Используешь ли ты **современный** API языка и пакетов проекта?
   - Dart 3 / текущий Flutter (null-safety, `super.key`, `switch`-выражения, `withValues`, актуальные `LocationSettings`)
   - Go 1.25: `errors.Is/As`, `%w`, `context` первым аргументом, chi вместо самодельного роутинга, `pgx/v5` вместо `database/sql`-обёрток
   - PostGIS: `ST_GeomFromText(..., 4326)`, `ST_ClusterDBSCAN` — не изобретай свой формат координат  
   Не тащи устаревшие паттерны «из памяти 2019 года».

3. **Можно ли короче?**  
   Задай себе: «Можно ли выразить то же яснее и короче?»  
   Убери лишние переменные, вложенность, обёртки «на будущее».

4. **Масштабируемость**  
   Легко ли это расширить без копипаста?
   - конфиг / константы вместо размазанного хардкода
   - одна ответственность на функцию
   - границы модулей из ARCHITECTURE (UI ≠ сеть ≠ датчики ≠ ORM ≠ HTTP)

Если на любой пункт ответ «нет / не уверен» — **остановись, поправь подход**, потом пиши.

---

## Clean code

### Делай

- Имена, которые читаются без комментария (`sendDefect`, `ResolveLocationWKT`, не `doStuff` / `data2`).
- Функция / метод делает **одно** дело.
- Маленькие понятные блоки; ранняя проверка ошибок (guard clauses).
- DRY: общая логика — в одном месте (`ApiService`, `internal/service`, `internal/osrm`).
- KISS / YAGNI: решай текущую задачу, не строй framework «на вырост».
- Ошибки Go заворачивай с контекстом: `fmt.Errorf("ошибка вставки в БД: %w", err)`.
- При росте backend — новый сценарий оформляй как `service` + `handler` + роут в `cmd/api/main.go`, не раздувай `main.go` логикой.
- При росте app — новые экраны/сервисы по образцу существующих, не сваливай всё в `main.dart`.

### Не делай

- **Лишние комментарии.** Комментируй только *почему* (неочевидный trade-off, баг платформы), не *что* и так видно из кода.
- Комментарии-нарратив (`// увеличиваем счётчик`), закомментированный мёртвый код, TODO без контекста.
- Дублирование UI/HTTP/формул «чуть-чуть по-другому» в двух файлах.
- Магические числа без имени (пороги, URL, timeout) — выноси в константы рядом с использованием или в конфиг-модуль.
- Новые зависимости без явной необходимости и без согласования с существующим стеком.
- Секреты, пароли, прод-URL в новых местах без необходимости (уже есть tech debt в MVP — не размножай).
- Моковые данные, замаскированные под реальные: если блок пока заглушка, помечай это в tech debt, а не выдавай за готовую функциональность.

---

## Структура проекта

| Слой | Разрешено | Запрещено |
|------|-----------|-----------|
| `sensor_service.dart` | Датчики, пороги, вызов API | Виджеты, тема |
| `api_service.dart` | HTTP, токены, буфер логов, локальная статистика | Бизнес-пороги accel, разметка UI |
| `*_screen.dart` / `widgets/` | UI, локальный state, навигация | Дублировать POST/GET — только через `ApiService` |
| `achievement_service.dart` | Каталог и локальный прогресс достижений | Сетевые вызовы в обход `ApiService` |
| `internal/handler` | HTTP: декод payload, коды ответов, middleware | SQL и бизнес-правила |
| `internal/service` | Бизнес-логика (нормализация, кластеры, OTP, JWT) | Формирование HTTP-ответов |
| `internal/models` | DTO и JSON-теги | Логика и доступ к БД |
| `internal/database` | Пул `pgx`, схема/миграции | HTTP и бизнес-логика |
| `internal/osrm` | Внешний HTTP с timeout и fallback | Знание о схеме БД |
| `cmd/api/main.go` | Wiring, роуты, graceful shutdown | Копипаста SQL/логики из сервисов |

Соблюдай существующие имена: **`app/`** (package `road_pulse`) и **`backend/`** (module `road_pulse/backend`). Историческое имя `easyride_app` в Android-сборке и канале уведомлений менять только отдельной задачей.

---

## Стек-специфика

### Flutter / Dart

- `const` конструкторы где возможно.
- Отменяй подписки / dispose контроллеры (`StreamSubscription`, `TextEditingController`, `AnimationController`).
- Не блокируй UI-поток тяжёлой работой.
- Foreground task: entry-point (`startCallback`) и `SensorTaskHandler` — как сейчас; не ломай isolate-контракт (`FlutterForegroundTask.sendDataToMain` для логов).
- Тема и цвета — только через `context.colors` / `AppTheme`; не хардкодь цвета в экранах.
- Шрифты подключаются локально из `assets/fonts/`; не тащи `google_fonts`.
- Новые идентификаторы — **English**; user-facing строки UI можно на **русском** (как в текущем UI).

### Backend / Go

- Явные типы на публичных функциях и DTO; JSON-теги — в `internal/models`.
- Работа с БД только через пул `*pgxpool.Pool`; `context.Context` первым аргументом; не логируй секреты и полные PII.
- Geo: WKT + `ST_GeomFromText(..., 4326)`, SRID 4326, `GEOMETRY(Geometry, 4326)`.
- Внешние HTTP (OSRM): timeout и fallback (как в `osrm.Client.Nearest` — fail open к исходным координатам).
- Миграции — идемпотентные (`CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`) в `database.InitSchema`.
- Новые ENV-параметры — через `internal/config` с осмысленным fallback; секреты не коммитить.

---

## Контракты и документация

- Меняешь request/response API → синхронно обнови клиент (`api_service.dart` + экраны) **и** `README.md` / `ARCHITECTURE.md`.
- Добавил / удалил / переименовал публичный модуль, функцию или пакет → обнови `ARCHITECTURE.md`.
- Новая заглушка в UI или обходное решение — строка в «Tech debt» в `README.md`.
- Не коммить: `app/build/`, `app/.dart_tool/`, `backend/bin/`, `backend/.env`, секреты, локальные ключи.

---

## Порядок работы агента (рекомендуемый)

1. Прочитать задачу.
2. Открыть релевантные файлы + `ARCHITECTURE.md`.
3. Пройти **чеклист из 4 пунктов** выше.
4. Внести минимальный diff.
5. Проверить: нет дублей, имена ясные, нет мусорных комментариев.
6. При необходимости — обновить docs.
7. По возможности — сборка/линт/smoke: `go build ./...`, `go vet ./...`, `flutter analyze`, `curl /health`.

---

## Антипаттерны (запрещены)

```dart
// плохо: копипаста sendDefect в экране
http.post(Uri.parse('http://...'), body: ...);

// плохо: комментарий «что»
// отправляем post запрос
await ApiService.sendDefect(...);
```

```go
// плохо: SQL и бизнес-правило прямо в обработчике
func (h *TelemetryHandler) PostTelemetry(w http.ResponseWriter, r *http.Request) {
    _, _ = h.pool.Exec(r.Context(), "INSERT INTO telemetry ...")
}

// плохо: потеря контекста ошибки
if err != nil {
    return err
}
```

```dart
// хорошо: переиспользование
await ApiService.sendDefect(lat: lat, lon: lon, speed: speed, force: force);
```

```go
// хорошо: слой сервиса, контекст в ошибке
locationWKT, geomType := s.ResolveLocationWKT(ctx, payload)
if err != nil {
    return nil, fmt.Errorf("ошибка подготовки геометрии: %w", err)
}
```

```python
# хорошо: комментарий «почему» (если нужен)
# OSRM public rate-limits; fail open to raw GPS so we never drop the hit
```

---

## Краткий манифест

> Перед каждой новой функцией: **не дублируй → используй актуальный API → пиши короче → оставляй место для роста.**  
> Код должен читаться без комментариев. Документы — источник правды о структуре; код — источник правды о поведении.

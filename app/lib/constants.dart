/// Единые константы и пороги приложения «Дорожный пульс»
library;

// --- Ключи SharedPreferences ---
const String kKeyPendingDistanceMeters = 'pending_distance_meters';
const String kKeyThemeMode = 'theme_mode';

// --- Пороги скорости и силы дефектов полотна ---
/// Минимальная скорость движения для включения записи ударов ям (км/ч)
const double kMinDefectSpeedKmh = 20.0;

/// Базовый порог вертикального удара, м/с² (не g)
const double kBumpBaseThresholdMs2 = 7.0;

/// Прирост порога на каждый км/ч скорости (см. `bumpThresholdFor`)
const double kBumpSpeedFactor = 0.12;

/// Серьёзность — во сколько раз удар превысил порог обнаружения для своей скорости.
/// Стартовые значения: подбираются по распределению `raw_bump_force` на реальных проездах.
const double kSeverityMediumRatio = 2.0;
const double kSeverityHardRatio = 3.5;

/// Только для ответов старого сервера без `severity`: пороги нормализованной силы (L / M)
const double kSeverityHard = 30.0;
const double kSeverityMedium = 20.0;

// --- Классификация удара ---
/// Ширина одиночного импульса (в метрах пути), начиная с которой это лежачий полицейский, а не яма
const double kSpeedBumpPulseM = 1.5;

/// То же после торможения перед ударом: подъезд к бугру на малой скорости
const double kBrakedPulseM = 0.8;

/// Порог RMS вертикали для участка тряски (rough_road), м/с²
const double kRoughRmsThresholdMs2 = 1.5;

// --- Пороги одометра и фильтрации GPS ---
/// Минимальная дистанция шага для учёта одометром (метры)
const double kOdometerMinStepM = 0.6;

/// Максимальная дистанция шага между двумя точками (отсечение выбросов GPS, метры)
const double kOdometerMaxStepM = 300.0;

/// Максимально допустимая погрешность GPS-позиции для учёта пробега (метры)
const double kOdometerMaxAccuracyM = 80.0;

/// Порог накопления пробега в фоновом режиме для отправки на сервер (метры)
const double kDistanceBatchBackgroundM = 25.0;
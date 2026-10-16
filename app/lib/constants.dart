/// Единые константы и пороги приложения «Дорожный пульс»
library;

// --- Ключи SharedPreferences ---
const String kKeyPendingDistanceMeters = 'pending_distance_meters';

// --- Пороги скорости и силы дефектов полотна ---
/// Минимальная скорость движения для включения записи ударов ям (км/ч)
const double kMinDefectSpeedKmh = 20.0;

/// Порог силы для категории «ЖЁСТКО» (L)
const double kSeverityHard = 30.0;

/// Порог силы для категории «ЗАМЕТНО» (M)
const double kSeverityMedium = 20.0;

// --- Пороги одометра и фильтрации GPS ---
/// Минимальная дистанция шага для учёта одометром (метры)
const double kOdometerMinStepM = 0.6;

/// Максимальная дистанция шага между двумя точками (отсечение выбросов GPS, метры)
const double kOdometerMaxStepM = 300.0;

/// Максимально допустимая погрешность GPS-позиции для учёта пробега (метры)
const double kOdometerMaxAccuracyM = 80.0;

/// Порог накопления пробега для вывода лога на экране «Запись» (метры)
const double kDistanceBatchScreenM = 15.0;

/// Порог накопления пробега в фоновом режиме для отправки на сервер (метры)
const double kDistanceBatchBackgroundM = 25.0;
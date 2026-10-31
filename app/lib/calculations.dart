/// Единые константы и чистые расчетные функции приложения «Дорожный пульс»
library;

import 'constants.dart';

/// Расчёт очков рейтинга пользователя по регламентной формуле:
/// (Км * 10) + (Дефекты * 50) + (Награды * 100) + (Серия * 20)
int ratingFor(double km, int defects, int awards, int streak) {
  return (km * 10).round() +
      (defects * 50) +
      (awards * 100) +
      (streak * 20);
}

String communityBadgeText(int rating, {int? percentile}) {
  if (percentile != null) {
    if (percentile <= 0) return "Новый участник";
    if (percentile <= 1) return "Топ 1% сообщества";
    if (percentile <= 5) return "Топ 5% сообщества";
    if (percentile <= 10) return "Топ 10% сообщества";
    if (percentile <= 25) return "Топ 25% сообщества";
    if (percentile <= 50) return "Топ 50% сообщества";
    if (percentile <= 80) return "Топ 80% сообщества";
    return "Новый участник";
  }

  if (rating >= 2500) return "Топ 1% сообщества";
  if (rating >= 1500) return "Топ 5% сообщества";
  if (rating >= 800) return "Топ 10% сообщества";
  if (rating >= 400) return "Топ 25% сообщества";
  if (rating >= 200) return "Топ 50% сообщества";
  if (rating >= 50) return "Топ 80% сообщества";
  return "Новый участник";
}

/// Проверка допустимости шага перемещения для учёта одометром
bool isCountableStep(double distanceM, double accuracyM) {
  if (accuracyM > kOdometerMaxAccuracyM) {
    return false;
  }
  return distanceM >= kOdometerMinStepM && distanceM < kOdometerMaxStepM;
}

/// Серьёзность дефекта: 1 — ровно, 2 — заметно, 3 — жёстко.
/// Сервер присылает `severity`; для ответов старого сервера считаем по нормализованной силе.
int defectSeverity(Map<String, dynamic> defect) {
  final severity = defect['severity'];
  if (severity is num) return severity.toInt().clamp(1, 3);

  final force = ((defect['max_force'] ?? defect['bump_force'] ?? 0) as num).toDouble();
  if (force > kSeverityHard) return 3;
  if (force > kSeverityMedium) return 2;
  return 1;
}

/// Безопасный парсинг даты дефекта с переводом в локальный часовой пояс
DateTime parseDefectDate(dynamic rawDate) {
  if (rawDate != null) {
    final parsed = DateTime.tryParse(rawDate.toString());
    if (parsed != null) {
      return parsed.toLocal();
    }
  }
  return DateTime.now();
}

/// Проверка попадания даты дефекта в выбранный фильтр периода:
/// 0 — Сегодня, 1 — Неделя (<= 7 дней), 2 — Месяц (<= 30 дней), 3 — Всё время
bool isDateInFilterPeriod(DateTime defectDate, DateTime now, int filterIndex) {
  switch (filterIndex) {
    case 0: // Сегодня
      return defectDate.year == now.year &&
          defectDate.month == now.month &&
          defectDate.day == now.day;
    case 1: // Неделя
      final diff = now.difference(defectDate);
      return diff.inDays <= 7 && !diff.isNegative;
    case 2: // Месяц
      final diff = now.difference(defectDate);
      return diff.inDays <= 30 && !diff.isNegative;
    case 3: // Всё время
    default:
      return true;
  }
}
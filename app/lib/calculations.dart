library;

import 'dart:math' as math;

import 'constants.dart';



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


bool isCountableStep(double distanceM, double accuracyM) {
  if (accuracyM > kOdometerMaxAccuracyM) {
    return false;
  }
  return distanceM >= kOdometerMinStepM && distanceM < kOdometerMaxStepM;
}



int defectSeverity(Map<String, dynamic> defect) {
  final severity = defect['severity'];
  if (severity is num) return severity.toInt().clamp(1, 3);

  final force = ((defect['max_force'] ?? defect['bump_force'] ?? 0) as num).toDouble();
  if (force > kSeverityHard) return 3;
  if (force > kSeverityMedium) return 2;
  return 1;
}


DateTime parseDefectDate(dynamic rawDate) {
  if (rawDate != null) {
    final parsed = DateTime.tryParse(rawDate.toString());
    if (parsed != null) {
      return parsed.toLocal();
    }
  }
  return DateTime.now();
}



bool isDateInFilterPeriod(DateTime defectDate, DateTime now, int filterIndex) {
  switch (filterIndex) {
    case 0:
      return defectDate.year == now.year &&
          defectDate.month == now.month &&
          defectDate.day == now.day;
    case 1:
      final diff = now.difference(defectDate);
      return diff.inDays <= 7 && !diff.isNegative;
    case 2:
      final diff = now.difference(defectDate);
      return diff.inDays <= 30 && !diff.isNegative;
    case 3:
    default:
      return true;
  }
}


({double x, double y}) mercatorPixel(double lat, double lon, int zoom) {
  final scale = 256.0 * (1 << zoom);
  final rad = lat.clamp(-85.05112878, 85.05112878) * math.pi / 180;
  return (
    x: (lon + 180) / 360 * scale,
    y: (1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2 * scale,
  );
}

class GridCluster {
  const GridCluster({
    required this.lat,
    required this.lon,
    required this.count,
    required this.maxSeverity,
  });

  final double lat;
  final double lon;
  final int count;
  final int maxSeverity;
}


List<GridCluster> clusterByGrid(
  Iterable<({double lat, double lon, int severity})> points, {
  required int zoom,
  required double cellPx,
}) {
  final cells = <(int, int), ({double lat, double lon, int count, int maxSeverity})>{};
  for (final p in points) {
    final px = mercatorPixel(p.lat, p.lon, zoom);
    final key = ((px.x / cellPx).floor(), (px.y / cellPx).floor());
    final c = cells[key];
    cells[key] = c == null
        ? (lat: p.lat, lon: p.lon, count: 1, maxSeverity: p.severity)
        : (
            lat: c.lat + p.lat,
            lon: c.lon + p.lon,
            count: c.count + 1,
            maxSeverity: math.max(c.maxSeverity, p.severity),
          );
  }
  return [
    for (final c in cells.values)
      GridCluster(
        lat: c.lat / c.count,
        lon: c.lon / c.count,
        count: c.count,
        maxSeverity: c.maxSeverity,
      ),
  ];
}


int activityLevel(double meters, int defects) {
  final km = meters / 1000.0;
  if (km >= kActivityHighKm || defects >= kActivityHighDefects) return 3;
  if (km >= kActivityMidKm || defects >= kActivityMidDefects) return 2;
  if (meters > 0 || defects > 0) return 1;
  return 0;
}

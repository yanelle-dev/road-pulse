import 'package:geocoding/geocoding.dart';
import 'dart:ui' show Locale;
/// Подпись места дефекта. Название дороги приходит с сервера (OSRM знает дорогу, на которую
/// привязана яма); геокодер устройства возвращает ближайший дом и ограничивает частоту запросов,
/// поэтому он только запасной вариант, а ответ кэшируется.
class AddressService {
  static final Map<String, Future<String?>> _cache = {};

  /// Мгновенная подпись, если она есть в данных кластера.
  static String? fromDefect(Map<String, dynamic> defect) {
    final name = (defect['road_name'] as String?)?.trim();
    return (name == null || name.isEmpty) ? null : name;
  }

  static Future<String?> resolve(Map<String, dynamic> defect) {
    final known = fromDefect(defect);
    if (known != null) return Future.value(known);

    final lat = (defect['lat'] ?? defect['latitude']) as num?;
    final lon = (defect['lon'] ?? defect['longitude']) as num?;
    if (lat == null || lon == null) return Future.value(null);

    final key = '${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';
    return _cache.putIfAbsent(key, () => _geocode(lat.toDouble(), lon.toDouble()));
  }

  static Future<String?> _geocode(double lat, double lon) async {
    try {
      final placemarks = await Geocoding().placemarkFromCoordinates(lat, lon, locale: const Locale('ru', 'RU'),);
      if (placemarks.isEmpty) return null;
      final p = placemarks.first;
      final parts = [p.thoroughfare ?? p.street, p.locality]
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      return parts.isEmpty ? null : parts.join(', ');
    } catch (_) {
      return null;
    }
  }
}
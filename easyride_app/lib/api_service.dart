import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Тип события журнала — задаёт цвет строки на экране «Запись».
enum LogKind { ok, hit, warn }

class LogEntry {
  final String time;
  final String message;
  final LogKind kind;

  const LogEntry(this.time, this.message, this.kind);
}

class ApiService {
  static const String apiUrl = 'http://31.77.105.240:8000/api/v1/telemetry';

  static ValueNotifier<List<LogEntry>> logs = ValueNotifier(const []);

  /// isolate присылает строки с эмодзи-маркером типа события
  /// (🟢/✅ ok, ⚡/❌ hit, ⚠️/🛑 warn) — разбираем здесь, на UI-стороне.
  static void addLog(String raw) {
    final time = DateTime.now().toString().split(' ').last.substring(0, 8);
    final message = raw
        .replaceAll(RegExp(r'[🟢✅⚡❌⚠🛑️]'), '')
        .replaceFirst('ФОН:', '')
        .trim();
    final kind = switch (raw) {
      final String m when m.contains('✅') || m.contains('🟢') => LogKind.ok,
      final String m when m.contains('⚡') || m.contains('❌') => LogKind.hit,
      final String m when m.contains('⚠') || m.contains('🛑') => LogKind.warn,
      _ => LogKind.ok,
    };
    logs.value = [LogEntry(time, message, kind), ...logs.value];
  }

  static Future<bool> sendDefect({
    required double lat,
    required double lon,
    required double speed,
    required double force,
    String defectType = 'pothole',
    String infrastructureType = 'road',
    List<Map<String, dynamic>> trajectory = const [],
  }) async {
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': 'test_user_01',
          'latitude': lat,
          'longitude': lon,
          'speed_kmh': speed,
          'bump_force': force,
          'defect_type': defectType,
          'infrastructure_type': infrastructureType,
          'trajectory': trajectory,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getBumps() async {
    try {
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data as List).cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint("Ошибка загрузки карты: $e");
    }
    return const [];
  }
}

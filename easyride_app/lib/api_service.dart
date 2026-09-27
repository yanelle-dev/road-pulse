import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum LogKind { ok, hit, warn }

class LogEntry {
  final String time;
  final String message;
  final LogKind kind;

  const LogEntry(this.time, this.message, this.kind);
}

class VerifyResult {
  final bool success;
  final bool isNewUser;
  final String? errorMessage;

  const VerifyResult({
    required this.success,
    this.isNewUser = false,
    this.errorMessage,
  });
}

class ApiService {
  // 10.0.2.2 — адрес хоста для Android Emulator.
  // На сервере замените на: http://31.77.105.240:8001/api/v1           http://10.0.2.2:8000/api/v1
  static const String baseUrl = 'http://31.77.105.240:8001/api/v1';
  static const String apiUrl = '$baseUrl/telemetry';

  static ValueNotifier<List<LogEntry>> logs = ValueNotifier(const []);

  static const String _keyAccessToken = 'auth_access_token';
  static const String _keyRefreshToken = 'auth_refresh_token';
  static const String _keyUserPhone = 'auth_user_phone';
  static const String _keyUserName = 'auth_user_name';
  static const String _keyUserCity = 'auth_user_city';
  static const String _keyUserClearance = 'auth_user_clearance';

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

  // --- МЕТОДЫ АВТОРИЗАЦИИ И ПРОФИЛЯ ---

  static Future<bool> requestCode(String phone) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/request-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Ошибка запроса кода: $e");
      return false;
    }
  }

  static Future<VerifyResult> verifyCode(String phone, String code) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/verify-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'code': code}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();

        await prefs.setString(_keyAccessToken, data['access_token'] ?? '');
        await prefs.setString(_keyRefreshToken, data['refresh_token'] ?? '');

        bool isNew = true;
        if (data['is_new_user'] != null) {
          isNew = data['is_new_user'] == true;
        }

        if (data['user'] != null) {
          final u = data['user'];
          final name = u['name']?.toString().trim() ?? '';
          final city = u['city']?.toString().trim() ?? '';
          final clearance = u['car_clearance'];

          await prefs.setString(_keyUserPhone, u['phone'] ?? phone);
          await prefs.setString(_keyUserName, name);
          await prefs.setString(_keyUserCity, city);
          await prefs.setInt(
            _keyUserClearance,
            clearance is int ? clearance : 0,
          );

          // Если имя и город уже сохранены в базе, считаем пользователя существующим
          if (name.isNotEmpty && city.isNotEmpty) {
            isNew = false;
          }
        }

        return VerifyResult(success: true, isNewUser: isNew);
      }

      final errorData = jsonDecode(response.body);
      return VerifyResult(
        success: false,
        errorMessage: errorData['detail'] ?? 'Ошибка проверки кода',
      );
    } catch (e) {
      debugPrint("Ошибка проверки кода: $e");
      return const VerifyResult(success: false, errorMessage: 'Ошибка сети');
    }
  }

  static Future<bool> updateProfile({
    required String name,
    required String city,
    required int clearance,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyUserName, name);
      await prefs.setString(_keyUserCity, city);
      await prefs.setInt(_keyUserClearance, clearance);

      final token = prefs.getString(_keyAccessToken);
      if (token != null && token.isNotEmpty) {
        await http.patch(
          Uri.parse('$baseUrl/auth/me'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'name': name,
            'city': city,
            'car_clearance': clearance,
          }),
        );
      }
      return true;
    } catch (e) {
      debugPrint("Ошибка обновления профиля: $e");
      return false;
    }
  }

  static Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAccessToken);
  }

  static Future<bool> isAuthenticated() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  static Future<Map<String, dynamic>> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'phone': prefs.getString(_keyUserPhone) ?? '+7 999 123-45-67',
      'name': prefs.getString(_keyUserName) ?? 'Водитель',
      'city': prefs.getString(_keyUserCity) ?? 'Москва',
      'car_clearance': prefs.getInt(_keyUserClearance) ?? 0,
    };
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyUserPhone);
    await prefs.remove(_keyUserName);
    await prefs.remove(_keyUserCity);
    await prefs.remove(_keyUserClearance);
  }

  // --- ТЕЛЕМЕТРИЯ ---

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
      final token = await getAccessToken();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: headers,
        body: jsonEncode({
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

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'achievement_service.dart';

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

/// Модель одного дня для теплокарты активности
class DayActivity {
  final DateTime date;
  final int count;
  final int level;
  final bool isToday;
  final bool isFuture;

  const DayActivity({
    required this.date,
    required this.count,
    required this.level,
    required this.isToday,
    required this.isFuture,
  });
}

/// Агрегированные данные активности за 28 дней
class UserActivityData {
  final List<DayActivity> days;
  final int streakDays;
  final int totalVisits;
  final int activeDays;

  const UserActivityData({
    required this.days,
    required this.streakDays,
    required this.totalVisits,
    required this.activeDays,
  });

  factory UserActivityData.empty() {
    return UserActivityData(
      days: List.generate(
        28,
        (i) => DayActivity(
          date: DateTime.now(),
          count: 0,
          level: 0,
          isToday: false,
          isFuture: false,
        ),
      ),
      streakDays: 0,
      totalVisits: 0,
      activeDays: 0,
    );
  }
}

/// Пользовательская статистика для экрана профиля
class UserStats {
  final double totalKm;
  final int totalDefects;
  final int rating;
  final int savedSuspensions;
  final int unlockedAchievements;
  final int streakDays;

  const UserStats({
    required this.totalKm,
    required this.totalDefects,
    required this.rating,
    required this.savedSuspensions,
    required this.unlockedAchievements,
    required this.streakDays,
  });

  factory UserStats.empty() {
    return const UserStats(
      totalKm: 0.0,
      totalDefects: 0,
      rating: 0,
      savedSuspensions: 0,
      unlockedAchievements: 0,
      streakDays: 0,
    );
  }
}

class ApiService {
  static const String baseUrl = 'http://31.77.105.240:8001/api/v1';
  static const String apiUrl = '$baseUrl/telemetry';

  static ValueNotifier<List<LogEntry>> logs = ValueNotifier(const []);

  static const String _keyAccessToken = 'auth_access_token';
  static const String _keyRefreshToken = 'auth_refresh_token';
  static const String _keyUserPhone = 'auth_user_phone';
  static const String _keyUserName = 'auth_user_name';
  static const String _keyUserCity = 'auth_user_city';
  static const String _keyUserClearance = 'auth_user_clearance';
  static const String _keyActivityVisits = 'user_activity_visits';
  static const String _keyDefectsCount = 'user_defects_count';

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

  // --- МЕТОДЫ УЧЁТА ДЕФЕКТОВ И РАСЧЁТА РЕЙТИНГА ---

  static Future<int> getDefectsCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyDefectsCount) ?? 0;
  }

  static Future<void> incrementDefectsCount([int delta = 1]) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_keyDefectsCount) ?? 0;
    final next = current + delta;
    await prefs.setInt(_keyDefectsCount, next);
    await AchievementService.syncDefectsProgress(next);
  }

  /// Получение сводной статистики и расчёт рейтинга по регламентной формуле
  static Future<UserStats> getUserStats() async {
    try {
      final totalKm = await AchievementService.getTotalDistanceKm();
      final totalDefects = await getDefectsCount();

      final activity = await getActivityData();
      final streakDays = activity.streakDays;

      final achievements = await AchievementService.getAchievements();
      final unlockedAchievements = achievements.where((a) => a.isUnlocked).length;

      // Формула: (Км * 10) + (Дефекты * 50) + (Награды * 100) + (Серия * 20)
      final rating = (totalKm * 10).round() +
          (totalDefects * 50) +
          (unlockedAchievements * 100) +
          (streakDays * 20);

      final savedSuspensions = (totalDefects * 0.15).ceil();

      return UserStats(
        totalKm: totalKm,
        totalDefects: totalDefects,
        rating: rating,
        savedSuspensions: savedSuspensions,
        unlockedAchievements: unlockedAchievements,
        streakDays: streakDays,
      );
    } catch (e) {
      debugPrint("Ошибка расчёта статистики: $e");
      return UserStats.empty();
    }
  }

  // --- МЕТОДЫ АКТИВНОСТИ ПОЛЬЗОВАТЕЛЯ (ЛОКАЛЬНО) ---

  static String _formatDateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static Future<void> recordAppOpen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyActivityVisits);
      Map<String, int> visits = {};

      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          visits = decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
        } catch (_) {}
      }

      final todayKey = _formatDateKey(DateTime.now());
      visits[todayKey] = (visits[todayKey] ?? 0) + 1;

      final cutoff = DateTime.now().subtract(const Duration(days: 90));
      visits.removeWhere((key, _) {
        try {
          return DateTime.parse(key).isBefore(cutoff);
        } catch (_) {
          return true;
        }
      });

      await prefs.setString(_keyActivityVisits, jsonEncode(visits));
    } catch (e) {
      debugPrint("Ошибка сохранения активности: $e");
    }
  }

  static Future<UserActivityData> getActivityData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyActivityVisits);
      Map<String, int> visits = {};

      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          visits = decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
        } catch (_) {}
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final todayKey = _formatDateKey(today);

      if (!visits.containsKey(todayKey)) {
        visits[todayKey] = 1;
        await prefs.setString(_keyActivityVisits, jsonEncode(visits));
      }

      final currentWeekMonday = today.subtract(
        Duration(days: today.weekday - 1),
      );
      final gridStartDate = currentWeekMonday.subtract(
        const Duration(days: 21),
      );

      final List<DayActivity> days = [];
      int totalVisits = 0;
      int activeDays = 0;

      for (int i = 0; i < 28; i++) {
        final cellDate = gridStartDate.add(Duration(days: i));
        final key = _formatDateKey(cellDate);
        final isFuture = cellDate.isAfter(today);
        final count = isFuture ? 0 : (visits[key] ?? 0);

        int level = 0;
        if (count >= 6) {
          level = 3;
        } else if (count >= 3) {
          level = 2;
        } else if (count >= 1) {
          level = 1;
        }

        if (count > 0) {
          totalVisits += count;
          activeDays++;
        }

        days.add(
          DayActivity(
            date: cellDate,
            count: count,
            level: level,
            isToday: key == todayKey,
            isFuture: isFuture,
          ),
        );
      }

      int streak = 0;
      DateTime checkDate = today;
      while (true) {
        final key = _formatDateKey(checkDate);
        final count = visits[key] ?? 0;
        if (count > 0) {
          streak++;
          checkDate = checkDate.subtract(const Duration(days: 1));
        } else {
          break;
        }
      }

      return UserActivityData(
        days: days,
        streakDays: streak,
        totalVisits: totalVisits,
        activeDays: activeDays,
      );
    } catch (e) {
      debugPrint("Ошибка получения активности: $e");
      return UserActivityData.empty();
    }
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

// --- ТЕЛЕМЕТРИЯ ДЕФЕКТОВ И ДИСТАНЦИИ ---

  /// Отправка пачки пройденных метров на сервер (любая скорость)
  static Future<bool> sendDistance(double meters) async {
    if (meters <= 0) return true;
    try {
      final token = await getAccessToken();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http.post(
        Uri.parse('$baseUrl/telemetry/distance'),
        headers: headers,
        body: jsonEncode({
          'distance_meters': meters,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Ошибка отправки дистанции на сервер: $e");
      return false;
    }
  }
  /// Отправка дефекта: счётчик инкрементируется ТОЛЬКО при успешном ответе HTTP 200
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

      if (response.statusCode == 200) {
        await incrementDefectsCount(1);
        return true;
      }
      return false;
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
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'achievement_service.dart';
import 'calculations.dart';
import 'constants.dart';
import 'fresh_prefs.dart';

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

/// Данные завершённой поездки пользователя
class TripData {
  final int id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double distanceMeters;
  final int defectsCount;
  final double smoothRatio;
  final double mediumRatio;
  final double hardRatio;

  const TripData({
    required this.id,
    required this.startedAt,
    this.endedAt,
    required this.distanceMeters,
    required this.defectsCount,
    required this.smoothRatio,
    required this.mediumRatio,
    required this.hardRatio,
  });

  factory TripData.fromJson(Map<String, dynamic> json) {
    return TripData(
      id: (json['id'] as num).toInt(),
      startedAt: DateTime.tryParse(json['started_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      endedAt: json['ended_at'] != null ? DateTime.tryParse(json['ended_at'].toString())?.toLocal() : null,
      distanceMeters: ((json['distance_meters'] ?? 0.0) as num).toDouble(),
      defectsCount: ((json['defects_count'] ?? 0) as num).toInt(),
      smoothRatio: ((json['smooth_ratio'] ?? 1.0) as num).toDouble(),
      mediumRatio: ((json['medium_ratio'] ?? 0.0) as num).toDouble(),
      hardRatio: ((json['hard_ratio'] ?? 0.0) as num).toDouble(),
    );
  }
}

/// Комментарий водителя к дефекту
class DefectComment {
  final int id;
  final int clusterId;
  final String authorName;
  final String text;
  final DateTime createdAt;

  const DefectComment({
    required this.id,
    required this.clusterId,
    required this.authorName,
    required this.text,
    required this.createdAt,
  });

  factory DefectComment.fromJson(Map<String, dynamic> json) {
    return DefectComment(
      id: (json['id'] as num).toInt(),
      clusterId: (json['cluster_id'] as num).toInt(),
      authorName: json['author_name']?.toString() ?? 'Водитель',
      text: json['text']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
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
  final int communityPercentile;

  const UserStats({
    required this.totalKm,
    required this.totalDefects,
    required this.rating,
    required this.savedSuspensions,
    required this.unlockedAchievements,
    required this.streakDays,
    this.communityPercentile = 0,
  });

  factory UserStats.empty() {
    return const UserStats(
      totalKm: 0.0,
      totalDefects: 0,
      rating: 0,
      savedSuspensions: 0,
      unlockedAchievements: 0,
      streakDays: 0,
      communityPercentile: 0,
    );
  }
}

/// Итог отправки дефекта: HTTP-статус (0 — сеть/таймаут) и признак повтора.
class DefectSendResult {
  final int status;

  /// Сервер уже знает эту яму (повтор события или тот же проезд): в счётчик она не идёт.
  final bool duplicate;

  const DefectSendResult(this.status, {this.duplicate = false});
}

class ApiService {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://64.188.74.105:8001/api/v1',
  );
  static const String apiUrl = '$baseUrl/telemetry';

  static ValueNotifier<List<LogEntry>> logs = ValueNotifier(const []);

  static const String _keyAccessToken = 'auth_access_token';
  static const String _keyRefreshToken = 'auth_refresh_token';

  static const Duration _httpTimeout = Duration(seconds: 12);

  /// Общий клиент: `http.post(...)` открывал новое соединение на каждый запрос.
  static final http.Client _client = http.Client();
  static Future<bool>? _refreshInFlight;

  /// Access-токен с автообновлением: если он истекает в ближайшие 60 с,
  /// меняем его по refresh-токену (раньше refresh нигде не использовался).
  static Future<String?> getValidAccessToken() async {
    final prefs = await freshPrefs();
    final token = prefs.getString(_keyAccessToken);
    if (token == null || token.isEmpty) return null;
    if (!_isExpiring(token)) return token;
    await refreshTokens();
    final p2 = await freshPrefs();
    final t2 = p2.getString(_keyAccessToken);
    return (t2 == null || t2.isEmpty) ? null : t2;
  }

  static bool _isExpiring(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return false;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      final exp = (payload['exp'] as num?)?.toInt();
      if (exp == null) return false;
      return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= exp - 60;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> refreshTokens() {
    return _refreshInFlight ??=
        _doRefresh().whenComplete(() => _refreshInFlight = null);
  }

  static Future<bool> _doRefresh() async {
    try {
      final prefs = await freshPrefs();
      final rt = prefs.getString(_keyRefreshToken);
      if (rt == null || rt.isEmpty) return false;
      final oldAccess = prefs.getString(_keyAccessToken);

      final res = await _client
          .post(
            Uri.parse('$baseUrl/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': rt}),
          )
          .timeout(_httpTimeout);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final access = data['access_token'] as String?;
        final refresh = data['refresh_token'] as String?;
        if (access == null || access.isEmpty || refresh == null || refresh.isEmpty) {
          return false;
        }
        final p = await SharedPreferences.getInstance();
        await p.setString(_keyAccessToken, access);
        await p.setString(_keyRefreshToken, refresh);
        return true;
      }
      // refresh ротируется: другой изолят мог уже обновить пару.
      final p2 = await freshPrefs();
      final rotatedElsewhere = p2.getString(_keyAccessToken) != oldAccess;
      // Refresh отозван или истёк: токен «лежит» в хранилище, но пользователь уже не авторизован.
      if (!rotatedElsewhere && res.statusCode == 401) await _clearSession();
      return rotatedElsewhere;
    } catch (_) {
      return false;
    }
  }
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
    final prefs = await freshPrefs();
    return prefs.getInt(_keyDefectsCount) ?? 0;
  }

  static Future<void> incrementDefectsCount([int delta = 1]) async {
    final prefs = await freshPrefs();
    final current = prefs.getInt(_keyDefectsCount) ?? 0;
    final next = current + delta;
    await prefs.setInt(_keyDefectsCount, next);
    await AchievementService.syncDefectsProgress(next);
  }

/// Получение сводной статистики: сервер как единственный источник правды
  static Future<UserStats> getUserStats() async {
    try {
      final token = await getAccessToken();
      final activity = await getActivityData();
      final streakDays = activity.streakDays;

      final achievements = await AchievementService.getAchievements();
      final unlockedAchievements = achievements.where((a) => a.isUnlocked).length;

      double totalKm = 0.0;
      int totalDefects = 0;
      int rating = 0;
      int savedSuspensions = 0;
      int communityPercentile = 0;
      bool serverDataLoaded = false;

      if (token != null && token.isNotEmpty) {
        try {
          // Один атомарный запрос: передаёт серию/награды и сразу возвращает эталонную статистику
          final res = await _client.post(
            Uri.parse('$baseUrl/auth/sync-stats'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'streak_days': streakDays,
              'unlocked_achievements': unlockedAchievements,
            }),
          ).timeout(_httpTimeout);

          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final serverMeters = (data['total_distance_meters'] ?? 0.0).toDouble();
            final prefs = await freshPrefs();
            final pendingMeters = prefs.getDouble(kKeyPendingDistanceMeters) ?? 0.0;

            totalKm = (serverMeters + pendingMeters) / 1000.0;
            totalDefects = (data['total_defects'] ?? 0) as int;
            rating = (data['rating'] ?? 0) as int;
            savedSuspensions = (data['saved_suspensions'] ?? 0) as int;
            communityPercentile = ((data['community_percentile'] ?? 0) as num).toInt();
            serverDataLoaded = true;
          }
        } catch (_) {}
      }

      // Оффлайн-фолбэк
      if (!serverDataLoaded) {
        totalKm = await AchievementService.getTotalDistanceKm();
        totalDefects = await getDefectsCount();
        rating = ratingFor(
          totalKm,
          totalDefects,
          unlockedAchievements,
          streakDays,
        );
        savedSuspensions = (totalDefects * 0.15).ceil();
      }

      return UserStats(
        totalKm: totalKm,
        totalDefects: totalDefects,
        rating: rating,
        savedSuspensions: savedSuspensions,
        unlockedAchievements: unlockedAchievements,
        streakDays: streakDays,
        communityPercentile: communityPercentile,
      );
    } catch (e) {
      debugPrint("Ошибка расчёта статистики: $e");
      return UserStats.empty();
    }
  }

  // --- МЕТОДЫ ПОЕЗДОК ---

  static Future<int?> startTrip() async {
    try {
      final token = await getAccessToken();
      if (token == null || token.isEmpty) return null;

      final res = await _client.post(
        Uri.parse('$baseUrl/trips/start'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_httpTimeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['trip_id'] as num?)?.toInt();
      }
    } catch (e) {
      debugPrint("Ошибка старта поездки: $e");
    }
    return null;
  }

  static Future<bool> finishTrip({
    required int tripId,
    required double distanceMeters,
    required int defectsCount,
    double smoothRatio = 0.70,
    double mediumRatio = 0.20,
    double hardRatio = 0.10,
  }) async {
    try {
      final token = await getAccessToken();
      if (token == null || token.isEmpty) return false;

      final res = await _client.post(
        Uri.parse('$baseUrl/trips/finish'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'trip_id': tripId,
          'distance_meters': distanceMeters,
          'defects_count': defectsCount,
          'smooth_ratio': smoothRatio,
          'medium_ratio': mediumRatio,
          'hard_ratio': hardRatio,
        }),
      ).timeout(_httpTimeout);
      return res.statusCode == 200;
    } catch (e) {
      debugPrint("Ошибка завершения поездки: $e");
      return false;
    }
  }

  static Future<TripData?> getLastTrip() async {
    try {
      final token = await getAccessToken();
      if (token == null || token.isEmpty) return null;

      final res = await _client.get(
        Uri.parse('$baseUrl/trips/last'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(_httpTimeout);
      if (res.statusCode == 200 && res.body.isNotEmpty && res.body != "null") {
        final data = jsonDecode(res.body);
        if (data != null && data is Map<String, dynamic> && data['id'] != null) {
          return TripData.fromJson(data);
        }
      }
    } catch (e) {
      debugPrint("Ошибка получения последней поездки: $e");
    }
    return null;
  }

  // --- КОММЕНТАРИИ К ДЕФЕКТАМ ---

  static Future<List<DefectComment>> getComments(int clusterId) async {
    try {
      final res = await _client.get(Uri.parse('$baseUrl/telemetry/comments?cluster_id=$clusterId')).timeout(_httpTimeout);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        return list.map((item) => DefectComment.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint("Ошибка получения комментариев: $e");
    }
    return [];
  }

  static Future<bool> addComment({required int clusterId, required String text}) async {
    try {
      final token = await getAccessToken();
      if (token == null || token.isEmpty) return false;
      final profile = await getUserProfile();
      final authorName = profile['name']?.toString() ?? 'Водитель';

      final res = await _client.post(
        Uri.parse('$baseUrl/telemetry/comments'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'cluster_id': clusterId,
          'text': text,
          'author_name': authorName,
        }),
      ).timeout(_httpTimeout);
      return res.statusCode == 200;
    } catch (e) {
      debugPrint("Ошибка отправки комментария: $e");
    }
    return false;
  }

  // --- МЕТОДЫ АКТИВНОСТИ ПОЛЬЗОВАТЕЛЯ ---

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

  static Future<String?> requestCode(String phone) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/auth/request-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      ).timeout(_httpTimeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['code']?.toString() ?? '';
      }
      return null;
    } catch (e) {
      debugPrint("Ошибка запроса кода: $e");
      return null;
    }
  }

  static Future<VerifyResult> verifyCode(String phone, String code) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/auth/verify-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'code': code}),
      ).timeout(_httpTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();

        await prefs.setString(_keyAccessToken, data['access_token'] ?? '');
        await prefs.setString(_keyRefreshToken, data['refresh_token'] ?? '');

        await flushPendingDistance();

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
        await _client.patch(
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
        ).timeout(_httpTimeout);
      }
      return true;
    } catch (e) {
      debugPrint("Ошибка обновления профиля: $e");
      return false;
    }
  }

  static Future<String?> getAccessToken() => getValidAccessToken();

  static Future<bool> isAuthenticated() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  static Future<Map<String, dynamic>> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'phone': prefs.getString(_keyUserPhone) ?? '',
      'name': prefs.getString(_keyUserName) ?? 'Водитель',
      'city': prefs.getString(_keyUserCity) ?? 'Москва',
      'car_clearance': prefs.getInt(_keyUserClearance) ?? 0,
    };
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(_keyRefreshToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await _client.post(
          Uri.parse('$baseUrl/auth/logout'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': refreshToken}),
        ).timeout(_httpTimeout);
      } catch (_) {}
    }
    await _clearSession();
  }

  static Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      _keyAccessToken,
      _keyRefreshToken,
      _keyUserPhone,
      _keyUserName,
      _keyUserCity,
      _keyUserClearance,
    ]) {
      await prefs.remove(key);
    }
  }

  /// Серверное удаление аккаунта с анонимизацией телеметрии
  static Future<bool> deleteAccount() async {
    try {
      final token = await getAccessToken();
      if (token == null || token.isEmpty) return false;

      final res = await _client.delete(
        Uri.parse('$baseUrl/auth/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_httpTimeout);
      if (res.statusCode == 200) {
        await logout();
        return true;
      }
    } catch (e) {
      debugPrint("Ошибка удаления аккаунта: $e");
    }
    return false;
  }

  // --- ТЕЛЕМЕТРИЯ ДЕФЕКТОВ И ДИСТАНЦИИ ---

  static Future<bool> sendDistance(double meters) async {
    if (meters <= 0) return true;
    try {
      final token = await getAccessToken();
      if (token == null || token.isEmpty) {
        return false;
      }

      final response = await _client.post(
        Uri.parse('$baseUrl/telemetry/distance'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'distance_meters': meters,
        }),
      ).timeout(_httpTimeout);
      if (response.statusCode != 200) return false;
      // Для гостя/невалидного токена сервер отвечает 200, но ничего не пишет (total = 0).
      final data = jsonDecode(response.body);
      final total = (data['total_distance_meters'] as num?)?.toDouble() ?? 0.0;
      return total > 0;
    } catch (e) {
      debugPrint("Ошибка отправки дистанции на сервер: $e");
      return false;
    }
  }

  static Future<void> flushPendingDistance() async {
    try {
      final token = await getAccessToken();
      if (token == null || token.isEmpty) return;

      final prefs = await freshPrefs();
      final pending = prefs.getDouble(kKeyPendingDistanceMeters) ?? 0.0;
      if (pending <= 0) return;

      final success = await sendDistance(pending);
      if (success) {
        final current = prefs.getDouble(kKeyPendingDistanceMeters) ?? 0.0;
        final remainder = current - pending;
        await prefs.setDouble(
          kKeyPendingDistanceMeters,
          remainder > 0 ? remainder : 0.0,
        );
        addLog("✅ Буфер пробега синхронизирован: +${pending.toStringAsFixed(0)} м");
      }
    } catch (e) {
      debugPrint("Ошибка сброса буфера пробега: $e");
    }
  }

  /// Без токена не отправляем: событие осталось бы «гостевым» и не попало бы в профиль.
  /// Статус 401 оставляет его в очереди до входа в аккаунт.
  static Future<DefectSendResult> sendDefectStatus({
    required double lat,
    required double lon,
    required double speed,
    required double force,
    String defectType = 'pothole',
    String infrastructureType = 'road',
    List<Map<String, dynamic>> trajectory = const [],
    int? eventTimeMs,
    String? clientEventId,
    double? headingDeg,
    double? accuracyM,
  }) async {
    try {
      final token = await getAccessToken();
      if (token == null || token.isEmpty) return const DefectSendResult(401);

      final response = await _client.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'latitude': lat,
          'longitude': lon,
          'speed_kmh': speed,
          'bump_force': force,
          'defect_type': defectType,
          'infrastructure_type': infrastructureType,
          'trajectory': trajectory,
          'event_time_ms': ?eventTimeMs,
          'client_event_id': ?clientEventId,
          'heading_deg': ?headingDeg,
          'accuracy_m': ?accuracyM,
        }),
      ).timeout(_httpTimeout);

      if (response.statusCode != 200) return DefectSendResult(response.statusCode);

      var duplicate = false;
      try {
        duplicate = (jsonDecode(response.body) as Map)['duplicate'] == true;
      } catch (_) {}
      if (!duplicate) await incrementDefectsCount(1);
      return DefectSendResult(200, duplicate: duplicate);
    } catch (e) {
      return const DefectSendResult(0);
    }
  }

  static Future<List<Map<String, dynamic>>> getBumps() async {
    try {
      final response = await _client.get(Uri.parse(apiUrl)).timeout(_httpTimeout);
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
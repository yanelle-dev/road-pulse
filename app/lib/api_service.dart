import 'dart:convert';
import 'dart:math' show Random, max, min;
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
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


class DayActivity {
  final DateTime date;

  final int count;
  final double meters;
  final int level;
  final bool isToday;
  final bool isFuture;

  const DayActivity({
    required this.date,
    required this.count,
    this.meters = 0.0,
    required this.level,
    required this.isToday,
    required this.isFuture,
  });
}


class UserActivityData {
  final List<DayActivity> days;
  final int streakDays;
  final double totalMeters;
  final int activeDays;

  const UserActivityData({
    required this.days,
    required this.streakDays,
    required this.totalMeters,
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
      totalMeters: 0.0,
      activeDays: 0,
    );
  }
}


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


class UserStats {
  final double totalKm;
  final int totalDefects;
  final int rating;
  final int savedSuspensions;
  final int unlockedAchievements;
  final int streakDays;
  final int communityPercentile;
  final int potholes;
  final int roughRoads;

  const UserStats({
    required this.totalKm,
    required this.totalDefects,
    required this.rating,
    required this.savedSuspensions,
    required this.unlockedAchievements,
    required this.streakDays,
    this.communityPercentile = 0,
    this.potholes = 0,
    this.roughRoads = 0,
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


class DefectSendResult {
  final int status;


  final bool duplicate;

  const DefectSendResult(this.status, {this.duplicate = false});
}

class ApiService {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://194.76.172.75:8001/api/v1',
  );
  static const String apiUrl = '$baseUrl/telemetry';

  static ValueNotifier<List<LogEntry>> logs = ValueNotifier(const []);

  static const String _keyAccessToken = 'auth_access_token';
  static const String _keyRefreshToken = 'auth_refresh_token';

  static const Duration _httpTimeout = Duration(seconds: 12);


  static final http.Client _client = http.Client();
  static Future<bool>? _refreshInFlight;



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

      final p2 = await freshPrefs();
      final rotatedElsewhere = p2.getString(_keyAccessToken) != oldAccess;

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


  static Future<UserStats> getUserStats() async {
    try {
      final token = await getAccessToken();
      final prefs = await freshPrefs();
      var streakDays = _activityFromCache(prefs).streakDays;
      int potholes = 0;
      int roughRoads = 0;

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

          final res = await _client.post(
            Uri.parse('$baseUrl/auth/sync-stats'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'unlocked_achievements': unlockedAchievements,
            }),
          ).timeout(_httpTimeout);

          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final serverMeters = (data['total_distance_meters'] ?? 0.0).toDouble();
            await prefs.reload();
            final pendingMeters = prefs.getDouble(kKeyPendingDistanceMeters) ?? 0.0;

            totalKm = (serverMeters + pendingMeters) / 1000.0;
            totalDefects = (data['total_defects'] ?? 0) as int;
            rating = (data['rating'] ?? 0) as int;
            savedSuspensions = (data['saved_suspensions'] ?? 0) as int;
            communityPercentile = ((data['community_percentile'] ?? 0) as num).toInt();
            streakDays = (data['streak_days'] as num?)?.toInt() ?? streakDays;
            potholes = (data['pothole_count'] as num?)?.toInt() ?? 0;
            roughRoads = (data['rough_road_count'] as num?)?.toInt() ?? 0;
            await _cacheActivity(prefs, data as Map<String, dynamic>);
            serverDataLoaded = true;
          }
        } catch (_) {}
      }


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
        potholes: potholes,
        roughRoads: roughRoads,
      );
    } catch (e) {
      debugPrint("Ошибка расчёта статистики: $e");
      return UserStats.empty();
    }
  }

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

  static String _formatDateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }



  static Future<UserActivityData> getActivityData() async {
    final prefs = await freshPrefs();
    final token = await getAccessToken();
    if (token != null && token.isNotEmpty) {
      try {
        final res = await _client.get(
          Uri.parse('$baseUrl/auth/me'),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(_httpTimeout);
        if (res.statusCode == 200) {
          await _cacheActivity(prefs, jsonDecode(res.body) as Map<String, dynamic>);
        }
      } catch (e) {
        debugPrint("Ошибка получения активности: $e");
      }
    }
    return _activityFromCache(prefs);
  }


  static Future<UserActivityData> getCachedActivityData() async {
    return _activityFromCache(await freshPrefs());
  }

  static Future<void> _cacheActivity(
    SharedPreferences prefs,
    Map<String, dynamic> profile,
  ) {
    return prefs.setString(
      kKeyActivityCache,
      jsonEncode({
        'streak_days': profile['streak_days'] ?? 0,
        'activity_days': profile['activity_days'] ?? const [],
      }),
    );
  }

  static UserActivityData _activityFromCache(SharedPreferences prefs) {
    Map<String, dynamic> cache = const {};
    try {
      final raw = prefs.getString(kKeyActivityCache);
      if (raw != null) cache = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {}

    final byDate = <String, ({double meters, int defects})>{};
    for (final d in (cache['activity_days'] as List?) ?? const []) {
      if (d is! Map) continue;
      byDate[d['date'].toString()] = (
        meters: (d['distance_meters'] as num?)?.toDouble() ?? 0.0,
        defects: (d['defects'] as num?)?.toInt() ?? 0,
      );
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayKey = _formatDateKey(today);
    final gridStartDay = today.day - (today.weekday - 1) - 21;

    final days = <DayActivity>[];
    var activeDays = 0;
    var totalMeters = 0.0;
    for (var i = 0; i < 28; i++) {
      final date = DateTime(today.year, today.month, gridStartDay + i);
      final key = _formatDateKey(date);
      final isFuture = date.isAfter(today);
      final day = isFuture ? null : byDate[key];
      final meters = day?.meters ?? 0.0;
      final defects = day?.defects ?? 0;
      final level = activityLevel(meters, defects);
      if (level > 0) activeDays++;
      totalMeters += meters;
      days.add(
        DayActivity(
          date: date,
          count: defects,
          meters: meters,
          level: level,
          isToday: key == todayKey,
          isFuture: isFuture,
        ),
      );
    }

    return UserActivityData(
      days: days,
      streakDays: (cache['streak_days'] as num?)?.toInt() ?? 0,
      totalMeters: totalMeters,
      activeDays: activeDays,
    );
  }


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

  static Future<bool> sendDistance(double meters, {String? batchId}) async {
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
          'batch_id': ?batchId,
        }),
      ).timeout(_httpTimeout);
      if (response.statusCode != 200) return false;

      final data = jsonDecode(response.body);
      final total = (data['total_distance_meters'] as num?)?.toDouble() ?? 0.0;
      return total > 0;
    } catch (e) {
      debugPrint("Ошибка отправки дистанции на сервер: $e");
      return false;
    }
  }




  static Future<double> sendPendingDistance(
    SharedPreferences prefs,
    double pending,
  ) async {
    var batchId = prefs.getString(kKeyDistanceBatchId);
    var meters = prefs.getDouble(kKeyDistanceBatchMeters) ?? 0.0;
    if (batchId == null || meters <= 0) {
      meters = min(pending, kMaxDistanceBatchM);
      if (meters <= 0) return 0.0;
      batchId =
          '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 31)}';
      await prefs.setString(kKeyDistanceBatchId, batchId);
      await prefs.setDouble(kKeyDistanceBatchMeters, meters);
    }

    if (!await sendDistance(meters, batchId: batchId)) return 0.0;
    await prefs.remove(kKeyDistanceBatchId);
    await prefs.remove(kKeyDistanceBatchMeters);
    return meters;
  }



  static Future<void> flushPendingDistance() async {
    try {
      if (await FlutterForegroundTask.isRunningService) return;
      final token = await getAccessToken();
      if (token == null || token.isEmpty) return;

      final prefs = await freshPrefs();
      var pending = prefs.getDouble(kKeyPendingDistanceMeters) ?? 0.0;
      while (pending > 0) {
        final sent = await sendPendingDistance(prefs, pending);
        if (sent <= 0) break;
        pending = max(pending - sent, 0.0);
        await prefs.setDouble(kKeyPendingDistanceMeters, pending);
        addLog("✅ Буфер пробега синхронизирован: +${sent.toStringAsFixed(0)} м");
      }
    } catch (e) {
      debugPrint("Ошибка сброса буфера пробега: $e");
    }
  }



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
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:road_pulse/api_service.dart';
import 'package:road_pulse/calculations.dart';
import 'package:road_pulse/constants.dart';
import 'package:road_pulse/fresh_prefs.dart';

void main() {
  group('communityBadgeText — процентили и ранги сообщества (№4, №12)', () {
    test('новые участники без пробега и дефектов получают бейдж «Новый участник»', () {
      expect(communityBadgeText(0, percentile: 0), "Новый участник");
      expect(communityBadgeText(100, percentile: 0), "Новый участник");
    });

    test('процентиль 1..80 отображает соответствующий топ', () {
      expect(communityBadgeText(0, percentile: 1), "Топ 1% сообщества");
      expect(communityBadgeText(0, percentile: 5), "Топ 5% сообщества");
      expect(communityBadgeText(0, percentile: 10), "Топ 10% сообщества");
      expect(communityBadgeText(0, percentile: 25), "Топ 25% сообщества");
      expect(communityBadgeText(0, percentile: 50), "Топ 50% сообщества");
      expect(communityBadgeText(0, percentile: 80), "Топ 80% сообщества");
      expect(communityBadgeText(0, percentile: 85), "Новый участник");
    });

    test('при отсутствии серверного процентиля (null) работает фолбэк по рейтингу', () {
      expect(communityBadgeText(0, percentile: null), "Новый участник");
      expect(communityBadgeText(49, percentile: null), "Новый участник");
      expect(communityBadgeText(50, percentile: null), "Топ 80% сообщества");
      expect(communityBadgeText(200, percentile: null), "Топ 50% сообщества");
      expect(communityBadgeText(400, percentile: null), "Топ 25% сообщества");
      expect(communityBadgeText(800, percentile: null), "Топ 10% сообщества");
      expect(communityBadgeText(1500, percentile: null), "Топ 5% сообщества");
      expect(communityBadgeText(2500, percentile: null), "Топ 1% сообщества");
    });
  });

  group('ratingFor — регламентная формула расчёта рейтинга (№3, №11)', () {
    test('нулевые показатели дают 0 очков', () {
      expect(ratingFor(0.0, 0, 0, 0), 0);
    });

    test('изолированный расчёт каждого слагаемого', () {
      expect(ratingFor(1.0, 0, 0, 0), 10);
      expect(ratingFor(0.0, 1, 0, 0), 50);
      expect(ratingFor(0.0, 0, 1, 0), 100);
      expect(ratingFor(0.0, 0, 0, 1), 20);
    });

    test('комплексный расчёт с округлением дробного километража', () {
      expect(ratingFor(12.34, 5, 3, 7), 813);
    });
  });

  group('isCountableStep — фильтрация шагов одометра (№1, №3)', () {
    test('границы допустимой дистанции шага (0.6м <= distance < 300м)', () {
      expect(isCountableStep(0.59, 20.0), isFalse);
      expect(isCountableStep(0.6, 20.0), isTrue);
      expect(isCountableStep(299.9, 20.0), isTrue);
      expect(isCountableStep(300.0, 20.0), isFalse);
    });

    test('границы погрешности GPS (accuracy <= 80.0м)', () {
      expect(isCountableStep(10.0, 80.0), isTrue);
      expect(isCountableStep(10.0, 80.1), isFalse);
      expect(isCountableStep(10.0, 120.0), isFalse);
    });

    test('комбинированный случай: верная дистанция, но плохая точность', () {
      expect(isCountableStep(50.0, 85.0), isFalse);
    });
  });

  group('freshPrefs — принудительная синхронизация SharedPreferences (№4)', () {
    test('возвращает актуальный экземпляр SharedPreferences с перезагрузкой с диска', () async {
      SharedPreferences.setMockInitialValues({'test_distance': 150.0});
      final prefs = await freshPrefs();
      expect(prefs.getDouble('test_distance'), 150.0);
    });
  });

  group('parseDefectDate — парсинг дат телеметрии (№5)', () {
    test('корректно парсит ISO 8601 строку из JSON', () {
      final dt = parseDefectDate("2026-10-15T12:30:00Z");
      expect(dt.year, 2026);
      expect(dt.month, 10);
      expect(dt.isUtc, isFalse);
    });

    test('при null или некорректной строке возвращает текущее время', () {
      final before = DateTime.now();
      final dtNull = parseDefectDate(null);
      final dtInvalid = parseDefectDate("invalid_date");
      final after = DateTime.now();

      expect(dtNull.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(dtInvalid.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });
  });

  group('isDateInFilterPeriod — фильтрация дефектов ленты (№5)', () {
    final now = DateTime(2026, 10, 15, 12, 0, 0);

    test('фильтр 0 (Сегодня)', () {
      final todayMorning = DateTime(2026, 10, 15, 8, 0, 0);
      final yesterday = DateTime(2026, 10, 14, 23, 59, 59);

      expect(isDateInFilterPeriod(todayMorning, now, 0), isTrue);
      expect(isDateInFilterPeriod(yesterday, now, 0), isFalse);
    });

    test('фильтр 1 (Неделя — <= 7 дней)', () {
      final sixDaysAgo = now.subtract(const Duration(days: 6));
      final eightDaysAgo = now.subtract(const Duration(days: 8));

      expect(isDateInFilterPeriod(sixDaysAgo, now, 1), isTrue);
      expect(isDateInFilterPeriod(eightDaysAgo, now, 1), isFalse);
    });

    test('фильтр 2 (Месяц — <= 30 дней)', () {
      final twentyDaysAgo = now.subtract(const Duration(days: 20));
      final thirtyFiveDaysAgo = now.subtract(const Duration(days: 35));

      expect(isDateInFilterPeriod(twentyDaysAgo, now, 2), isTrue);
      expect(isDateInFilterPeriod(thirtyFiveDaysAgo, now, 2), isFalse);
    });

    test('фильтр 3 (Всё время)', () {
      final yearAgo = now.subtract(const Duration(days: 365));
      expect(isDateInFilterPeriod(yearAgo, now, 3), isTrue);
    });
  });

  group('ApiService — конфигурация URL адресов через окружение (№6)', () {
    test('дефолтный baseUrl и apiUrl соответствуют спецификации', () {
      expect(ApiService.baseUrl, 'http://64.188.74.105:8001/api/v1');
      expect(ApiService.apiUrl, 'http://64.188.74.105:8001/api/v1/telemetry');
      expect(ApiService.baseUrl.endsWith('/'), isFalse);
    });
  });

  group('Константы приложения и ключи хранилища (№1, №8)', () {
    test('пороги одометра и скорости зафиксированы', () {
      expect(kMinDefectSpeedKmh, 20.0);
      expect(kSeverityHard, 30.0);
      expect(kSeverityMedium, 20.0);
      expect(kOdometerMinStepM, 0.6);
      expect(kOdometerMaxStepM, 300.0);
      expect(kOdometerMaxAccuracyM, 80.0);
      expect(kKeyPendingDistanceMeters, 'pending_distance_meters');
    });
  });

  group('TripData — контракт завершённой поездки (№15)', () {
    test('десериализация полей и расчёт долей дорожной ленты', () {
      final json = {
        'id': 42,
        'started_at': '2026-10-15T12:00:00Z',
        'ended_at': '2026-10-15T12:35:00Z',
        'distance_meters': 18450.0,
        'defects_count': 6,
        'smooth_ratio': 0.75,
        'medium_ratio': 0.15,
        'hard_ratio': 0.10,
      };

      final trip = TripData.fromJson(json);
      expect(trip.id, 42);
      expect(trip.distanceMeters, 18450.0);
      expect(trip.defectsCount, 6);
      expect(trip.smoothRatio + trip.mediumRatio + trip.hardRatio, closeTo(1.0, 0.001));
    });
  });

  group('Проверка артефактов сборки (№18)', () {
    test('Android build.gradle.kts содержит целевые namespace и applicationId com.roadpulse.app', () {
      final file = File('android/app/build.gradle.kts');
      expect(file.existsSync(), isTrue, reason: 'Файл build.gradle.kts должен существовать');
      final content = file.readAsStringSync();
      expect(content.contains('applicationId = "com.roadpulse.app"'), isTrue,
          reason: 'applicationId обязан быть com.roadpulse.app');
      expect(content.contains('namespace = "com.roadpulse.app"'), isTrue,
          reason: 'namespace обязан быть com.roadpulse.app');
      expect(content.contains('easyride_app'), isFalse,
          reason: 'Устаревший идентификатор easyride_app не должен присутствовать в Gradle-конфиге');
    });
  });

  group('DefectComment — контракт комментариев к дефекту (№16)', () {
    test('десериализация полей комментария', () {
      final json = {
        'id': 101,
        'cluster_id': 42,
        'author_name': 'Сергей М.',
        'text': 'Осторожно, глубокая яма в правой колее',
        'created_at': '2026-10-15T10:00:00Z',
      };

      final comment = DefectComment.fromJson(json);
      expect(comment.id, 101);
      expect(comment.clusterId, 42);
      expect(comment.authorName, 'Сергей М.');
      expect(comment.text, 'Осторожно, глубокая яма в правой колее');
    });
  });
}
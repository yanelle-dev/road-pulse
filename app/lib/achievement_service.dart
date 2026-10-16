import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'fresh_prefs.dart';

class Achievement {
  final String id;
  final String category;
  final String title;
  final String description;
  final IconData icon;
  final int current;
  final int target;
  final bool isUnlocked;

  const Achievement({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.icon,
    required this.current,
    required this.target,
    required this.isUnlocked,
  });

  double get progressRatio => (current / target).clamp(0.0, 1.0);
}

class AchievementService {
  static const String _keyProgress = 'achievements_progress_v1';
  static const String _keyDistanceMeters = 'achievements_total_distance_m';

  static const List<String> categories = [
    "Все",
    "Старт",
    "Водитель",
    "Житель",
    "Порядочный гражданин",
    "Моя яма",
    "Доверие и сообщество",
  ];

  static final List<Map<String, dynamic>> _catalog = [
    // 1. Старт
    {
      "id": "first_km",
      "cat": "Старт",
      "title": "Первый километр",
      "desc": "Первая поездка, записанная в фоне",
      "icon": Icons.route_rounded,
      "target": 1,
    },
    {
      "id": "car_profile",
      "cat": "Старт",
      "title": "Знаю свою машину",
      "desc": "Заполнен профиль автомобиля: марка, модель, шины",
      "icon": Icons.directions_car_filled_rounded,
      "target": 1,
    },
    {
      "id": "streak_7",
      "cat": "Старт",
      "title": "На связи",
      "desc": "7 дней подряд фоновая работа без сбоев",
      "icon": Icons.wifi_tethering_rounded,
      "target": 7,
    },

    // 2. Водитель
    {
      "id": "first_find",
      "cat": "Водитель",
      "title": "Первая находка",
      "desc": "Первая яма, найденная датчиками и подтверждённая другими",
      "icon": Icons.adjust_rounded,
      "target": 1,
    },
    {
      "id": "sharp_eye",
      "cat": "Водитель",
      "title": "Глаз-алмаз",
      "desc": "10 подтверждённых ям",
      "icon": Icons.remove_red_eye_rounded,
      "target": 10,
    },
    {
      "id": "road_scanner",
      "cat": "Водитель",
      "title": "Дорожный сканер",
      "desc": "100 подтверждённых ям",
      "icon": Icons.radar_rounded,
      "target": 100,
    },
    {
      "id": "pioneer",
      "cat": "Водитель",
      "title": "Первооткрыватель",
      "desc": "10 ям, о которых вы сообщили первым",
      "icon": Icons.explore_rounded,
      "target": 10,
    },
    {
      "id": "cartographer",
      "cat": "Водитель",
      "title": "Картограф",
      "desc": "100 км дорог, по которым ещё не было данных",
      "icon": Icons.map_rounded,
      "target": 100,
    },
    {
      "id": "thousand",
      "cat": "Водитель",
      "title": "Тысячник",
      "desc": "1000 км с включённым мониторингом",
      "icon": Icons.speed_rounded,
      "target": 1000,
    },
    {
      "id": "lane_accuracy",
      "cat": "Водитель",
      "title": "Точно в полосу",
      "desc": "20 ям, для которых определена полоса",
      "icon": Icons.view_column_rounded,
      "target": 20,
    },
    {
      "id": "benchmark",
      "cat": "Водитель",
      "title": "Эталон",
      "desc": "Машина прошла автокалибровку по 10 общим ямам",
      "icon": Icons.tune_rounded,
      "target": 10,
    },
    {
      "id": "yard_scout",
      "cat": "Водитель",
      "title": "Дворовый разведчик",
      "desc": "5 подтверждённых ям во дворах",
      "icon": Icons.home_work_rounded,
      "target": 5,
    },

    // 3. Житель
    {
      "id": "neighbor",
      "cat": "Житель",
      "title": "Сосед",
      "desc": "Первый ответ на вопрос «Здесь была яма?»",
      "icon": Icons.question_answer_rounded,
      "target": 1,
    },
    {
      "id": "witness",
      "cat": "Житель",
      "title": "Свидетель",
      "desc": "25 ответов, совпавших с итоговым решением",
      "icon": Icons.fact_check_rounded,
      "target": 25,
    },
    {
      "id": "word_of_honor",
      "cat": "Житель",
      "title": "Честное слово",
      "desc": "10 контрольных вопросов подряд без ошибок",
      "icon": Icons.verified_user_rounded,
      "target": 10,
    },
    {
      "id": "yard_watch",
      "cat": "Житель",
      "title": "Двор под присмотром",
      "desc": "Участие в подтверждении 5 ям у дома (расчёт на телефоне)",
      "icon": Icons.security_rounded,
      "target": 5,
    },

    // 4. Порядочный гражданин
    {
      "id": "first_shot",
      "cat": "Порядочный гражданин",
      "title": "Первый кадр",
      "desc": "Первое фото, прошедшее модерацию",
      "icon": Icons.camera_alt_rounded,
      "target": 1,
    },
    {
      "id": "photo_reporter",
      "cat": "Порядочный гражданин",
      "title": "Фоторепортёр",
      "desc": "10 подтверждённых фото",
      "icon": Icons.photo_library_rounded,
      "target": 10,
    },
    {
      "id": "tape_measure",
      "cat": "Порядочный гражданин",
      "title": "С рулеткой",
      "desc": "5 фото с замером размеров ямы",
      "icon": Icons.straighten_rounded,
      "target": 5,
    },
    {
      "id": "on_foot",
      "cat": "Порядочный гражданин",
      "title": "Пешком виднее",
      "desc": "5 подтверждённых ям, найденных без машины",
      "icon": Icons.directions_walk_rounded,
      "target": 5,
    },
    {
      "id": "before_after",
      "cat": "Порядочный гражданин",
      "title": "До и после",
      "desc": "Фото заделанной ямы, о которой сообщали ранее",
      "icon": Icons.compare_rounded,
      "target": 1,
    },

    // 5. Моя яма
    {
      "id": "applicant",
      "cat": "Моя яма",
      "title": "Заявитель",
      "desc": "Первая отправленная жалоба",
      "icon": Icons.assignment_late_rounded,
      "target": 1,
    },
    {
      "id": "saw_through",
      "cat": "Моя яма",
      "title": "Довёл до конца",
      "desc": "Первая яма, заделанная после вашей жалобы",
      "icon": Icons.task_alt_rounded,
      "target": 1,
    },
    {
      "id": "repair_crew",
      "cat": "Моя яма",
      "title": "Ремонтная бригада",
      "desc": "10 заделанных ям с вашим участием",
      "icon": Icons.construction_rounded,
      "target": 10,
    },
    {
      "id": "controller",
      "cat": "Моя яма",
      "title": "Контролёр",
      "desc": "Подтвердили ремонт 10 ям, ответив на «Заделали?»",
      "icon": Icons.checklist_rounded,
      "target": 10,
    },
    {
      "id": "stood_ground",
      "cat": "Моя яма",
      "title": "Не отступил",
      "desc": "Повторное обращение после истёкшего срока завершилось ремонтом",
      "icon": Icons.shield_rounded,
      "target": 1,
    },

    // 6. Доверие и сообщество
    {
      "id": "reliable_source",
      "cat": "Доверие и сообщество",
      "title": "Надёжный источник",
      "desc": "Репутация от 0,9 при 50 и более сообщениях",
      "icon": Icons.stars_rounded,
      "target": 50,
    },
    {
      "id": "spring_watch",
      "cat": "Доверие и сообщество",
      "title": "Весенний дозор",
      "desc": "20 подтверждённых ям за март–апрель",
      "icon": Icons.wb_sunny_rounded,
      "target": 20,
    },
    {
      "id": "pothole_free_street",
      "cat": "Доверие и сообщество",
      "title": "Улица без ям",
      "desc": "На улице вашего участия заделаны все подтверждённые дефекты",
      "icon": Icons.add_road_rounded,
      "target": 1,
    },
    {
      "id": "district_guardian",
      "cat": "Доверие и сообщество",
      "title": "Хранитель района",
      "desc": "Первое место в рейтинге района за месяц",
      "icon": Icons.military_tech_rounded,
      "target": 1,
    },
  ];

  static Future<Map<String, int>> _loadRawProgress() async {
    final prefs = await freshPrefs();
    final raw = prefs.getString(_keyProgress);
    if (raw == null || raw.isEmpty) {
      final initial = <String, int>{};
      await prefs.setString(_keyProgress, jsonEncode(initial));
      return initial;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveRawProgress(Map<String, int> progress) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyProgress, jsonEncode(progress));
  }

  /// Получение всех 30 наград с актуализированным прогрессом
  static Future<List<Achievement>> getAchievements() async {
    final progress = await _loadRawProgress();

    // Автоматическая сверка серии дней посещений
    try {
      final act = await ApiService.getActivityData();
      if (act.streakDays > 0) {
        progress['streak_7'] = act.streakDays;
      }
    } catch (_) {}

    // Автоматическая сверка наград по дефектам
    try {
      final defCount = await ApiService.getDefectsCount();
      if (defCount > 0) {
        progress['first_find'] = 1;
        progress['sharp_eye'] = defCount;
        progress['road_scanner'] = defCount;
      }
    } catch (_) {}

    return _catalog.map((item) {
      final id = item['id'] as String;
      final target = item['target'] as int;
      final cur = (progress[id] ?? 0).clamp(0, target * 2);

      return Achievement(
        id: id,
        category: item['cat'] as String,
        title: item['title'] as String,
        description: item['desc'] as String,
        icon: item['icon'] as IconData,
        current: cur,
        target: target,
        isUnlocked: cur >= target,
      );
    }).toList();
  }

  /// Получение общего накопленного расстояния в метрах
  static Future<double> getTotalDistanceMeters() async {
    final prefs = await freshPrefs();
    return prefs.getDouble(_keyDistanceMeters) ?? 0.0;
  }

  /// Получение общего накопленного расстояния в километрах
  static Future<double> getTotalDistanceKm() async {
    final meters = await getTotalDistanceMeters();
    return meters / 1000.0;
  }

  /// Накопление пройденного километража (вызывается из DetectScreen)
  static Future<void> addDistanceMeters(double meters) async {
    if (meters <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final totalMeters = (prefs.getDouble(_keyDistanceMeters) ?? 0.0) + meters;
    await prefs.setDouble(_keyDistanceMeters, totalMeters);

    final totalKm = (totalMeters / 1000.0).floor();
    final progress = await _loadRawProgress();

    if (totalKm >= 1) {
      progress['first_km'] = 1;
    }
    progress['thousand'] = totalKm;
    await _saveRawProgress(progress);
  }

  /// Синхронизация достижений при успешной отправке ямы на сервер
  static Future<void> syncDefectsProgress(int count) async {
    final progress = await _loadRawProgress();
    if (count >= 1) {
      progress['first_find'] = 1;
    }
    progress['sharp_eye'] = count;
    progress['road_scanner'] = count;
    await _saveRawProgress(progress);
  }

  /// Зачёт достижения «Знаю свою машину» (вызывается из AccountScreen)
  static Future<void> checkCarProfile({
    required String model,
    required String tires,
    int clearance = 0,
  }) async {
    final isFilled = model.trim().isNotEmpty && tires.trim().isNotEmpty;
    if (isFilled) {
      final progress = await _loadRawProgress();
      progress['car_profile'] = 1;
      await _saveRawProgress(progress);
    }
  }

  /// Инкремент произвольного достижения
  static Future<void> increment(String id, [int delta = 1]) async {
    final progress = await _loadRawProgress();
    progress[id] = (progress[id] ?? 0) + delta;
    await _saveRawProgress(progress);
  }
}
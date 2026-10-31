import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'achievement_service.dart';
import 'api_service.dart';
import 'constants.dart';
import 'detection.dart';
import 'fresh_prefs.dart';
import 'gps.dart';

@pragma('vm:entry-point')
void startCallback() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(SensorTaskHandler());
}

class TrajectoryPoint {
  final double lat;
  final double lon;
  final double timestamp;

  TrajectoryPoint(this.lat, this.lon, this.timestamp);

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lon': lon,
    'timestamp': timestamp,
  };
}

/// GPS-фикс: recvMs — момент получения по внутренним часам, wallMs — время самого фикса (эпоха, мс).
class _Fix {
  final Position pos;
  final int recvMs;
  final int wallMs;
  final double speedKmh;
  _Fix(this.pos, this.recvMs, this.wallMs, this.speedKmh);
}

class _SpeedPt {
  final int t;
  final double kmh;
  _SpeedPt(this.t, this.kmh);
}

/// Сэмпл ускорения: v — вертикаль (вдоль гравитации), h — горизонталь.
class _Sample {
  final int t;
  final double v;
  final double h;
  _Sample(this.t, this.v, this.h);
}

class SensorTaskHandler extends TaskHandler {
  // ---- Параметры алгоритма (подбирать по полевым данным) ----
  static const int _windowMs = 600; // окно захвата удара (оба моста)
  static const int _warmupMs = 2000; // прогрев оценки гравитации
  static const double _gyroRejectRadS = 5.0; // телефон взяли в руки / уронили
  static const int _postEventBlockMs = 1000;
  static const int _pulseGapMs = 40; // разрыв внутри одного импульса (смена знака отклика)
  static const double _roughForceScale = 5.0; // RMS -> «сила» для сервера
  static const double _roughMaxSpeedKmh = 60.0;
  static const int _roughCooldownMs = 10000;
  static const int _roughTrackSec = 5; // участок тряски — последние секунды, а не весь буфер
  static const int _fixHistory = 6;
  static const double _headingMinStepM = 3.0; // короче шаг — курс по двум фиксам ненадёжен
  static const double _maxExtrapolateSec = 2.5;
  static const int _maxQueue = 100;
  static const String _kQueueKey = 'pending_defects_v1';

  StreamSubscription? _accelSubscription;
  StreamSubscription? _gyroSubscription;
  StreamSubscription? _positionSubscription;

  final Stopwatch _clock = Stopwatch();
  int _clockOriginWallMs = 0;

  final GravityFilter _gravity = GravityFilter();

  // GPS
  final List<_Fix> _fixes = [];
  final List<_SpeedPt> _speedHist = [];
  final List<TrajectoryPoint> _trajectoryBuffer = [];

  // Окно удара
  List<_Sample>? _win;
  int _winStartT = 0;
  _Fix? _winFix;
  double _winGyroPeak = 0;
  int _blockedUntil = 0;

  // Плохая дорога: RMS по бинам 0.5 c
  final List<double> _bins = [];
  double _binSumSq = 0;
  int _binCount = 0;
  int _binStartT = 0;
  int _roughUntil = 0;

  // Одометр
  Position? _lastDistancePosition;
  double _pendingDistanceMeters = 0.0;
  double _tripDistanceMeters = 0.0;
  DateTime _lastDistanceSync = DateTime.now();
  DateTime _syncBackoffUntil = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _syncFuture;
  bool _pendingDirty = false;

  // Поездка
  int? _currentTripId;
  Future<void>? _tripStart;
  int _tripDefectsCount = 0;
  final Map<int, int> _segSeverity = {}; // сегмент 100 м -> 2 (medium) / 3 (hard)

  // Очередь неотправленных дефектов
  List<Map<String, dynamic>> _queue = [];
  bool _flushing = false;

  _Fix? get _lastFix => _fixes.isEmpty ? null : _fixes.last;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    FlutterForegroundTask.sendDataToMain("🟢 ФОН: Мониторинг запущен...");
    _clockOriginWallMs = DateTime.now().millisecondsSinceEpoch;
    _clock
      ..reset()
      ..start();
    _binStartT = 0;

    final prefs = await freshPrefs();
    _pendingDistanceMeters = prefs.getDouble(kKeyPendingDistanceMeters) ?? 0.0;
    _loadQueue(prefs);
    _tripDistanceMeters = 0.0;
    FlutterForegroundTask.sendDataToMain("TRIP:0.0");

    // Датчики подписываем ДО сетевых вызовов.
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: gpsStreamSettings(),
    ).listen(_onPosition, onError: (_) {});

    _accelSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 10),
    ).listen(_onAccel, onError: (_) {});

    _gyroSubscription = gyroscopeEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen((e) {
      if (_win == null) return;
      final w = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      if (w > _winGyroPeak) _winGyroPeak = w;
    }, onError: (_) {});

    _tripStart = _startTripSafe();
    _tripDefectsCount = 0;
    _segSeverity.clear();

    if (_pendingDistanceMeters > 0) {
      unawaited(_checkAndSyncDistance());
    }
  }

  Future<void> _startTripSafe() async {
    try {
      _currentTripId = await ApiService.startTrip();
    } catch (_) {}
  }

  // ======================= GPS =======================

  /// Время фикса из самого GPS: оно точнее момента получения (доставка занимает до секунды).
  /// Если часы GNSS и системные расходятся, берём момент получения.
  int _fixWallMs(Position p, int nowWall) {
    final wall = p.timestamp.millisecondsSinceEpoch;
    return (wall > nowWall + 200 || nowWall - wall > 3000) ? nowWall : wall;
  }

  void _onPosition(Position p) {
    final t = _clock.elapsedMilliseconds;
    final nowWall = DateTime.now().millisecondsSinceEpoch;
    final speedKmh = p.speed >= 0 ? p.speed * 3.6 : 0.0;
    final fix = _Fix(p, t, _fixWallMs(p, nowWall), speedKmh);
    _fixes.add(fix);
    if (_fixes.length > _fixHistory) _fixes.removeAt(0);

    if (p.accuracy <= 50) {
      _speedHist.add(_SpeedPt(t, speedKmh));
      _speedHist.removeWhere((s) => t - s.t > 10000);

      _trajectoryBuffer.add(TrajectoryPoint(p.latitude, p.longitude, fix.wallMs / 1000.0));
      if (_trajectoryBuffer.length > 10) _trajectoryBuffer.removeAt(0);
    }

    _updateDistance(p);
  }

  _Fix? _freshFix(int t, int maxAgeMs) {
    final f = _lastFix;
    if (f == null || t - f.recvMs > maxAgeMs) return null;
    return f;
  }

  /// Курс в точке _fixes[i]: по смещению от предыдущего фикса, а на малом шаге — по `heading` датчика.
  double? _courseAt(int i) {
    final cur = _fixes[i];
    if (i > 0) {
      final prev = _fixes[i - 1];
      final d = Geolocator.distanceBetween(
        prev.pos.latitude,
        prev.pos.longitude,
        cur.pos.latitude,
        cur.pos.longitude,
      );
      if (d >= _headingMinStepM) {
        final b = Geolocator.bearingBetween(
          prev.pos.latitude,
          prev.pos.longitude,
          cur.pos.latitude,
          cur.pos.longitude,
        );
        return (b + 360) % 360;
      }
    }
    final h = cur.pos.heading;
    return (cur.speedKmh > 10 && h >= 0 && h < 360) ? h : null;
  }

  /// Позиция на момент пика: между двумя фиксами — интерполяция, после последнего — экстраполяция по курсу.
  ({double lat, double lon, double? course}) _positionAt(int peakWallMs) {
    final n = _fixes.length;
    final last = _fixes[n - 1];
    final lastCourse = _courseAt(n - 1);

    for (int i = n - 1; i > 0; i--) {
      final a = _fixes[i - 1];
      final b = _fixes[i];
      if (peakWallMs >= a.wallMs && peakWallMs <= b.wallMs && b.wallMs > a.wallMs) {
        final k = (peakWallMs - a.wallMs) / (b.wallMs - a.wallMs);
        return (
          lat: a.pos.latitude + (b.pos.latitude - a.pos.latitude) * k,
          lon: a.pos.longitude + (b.pos.longitude - a.pos.longitude) * k,
          course: _courseAt(i) ?? lastCourse,
        );
      }
    }

    final first = _fixes.first;
    if (peakWallMs <= first.wallMs) {
      return (lat: first.pos.latitude, lon: first.pos.longitude, course: _courseAt(0));
    }

    var lat = last.pos.latitude;
    var lon = last.pos.longitude;
    final ageSec = min(_maxExtrapolateSec, (peakWallMs - last.wallMs) / 1000.0);
    if (ageSec > 0 && last.speedKmh > 5 && lastCourse != null) {
      final p = _project(lat, lon, lastCourse, last.speedKmh / 3.6 * ageSec);
      lat = p.$1;
      lon = p.$2;
    }
    return (lat: lat, lon: lon, course: lastCourse);
  }

  void _updateDistance(Position p) {
    if (p.accuracy > kOdometerMaxAccuracyM) return;
    final last = _lastDistancePosition;
    if (last == null) {
      _lastDistancePosition = p;
      return;
    }
    final d = Geolocator.distanceBetween(
      last.latitude,
      last.longitude,
      p.latitude,
      p.longitude,
    );
    // Микрошаг: опорную точку НЕ сдвигаем, иначе медленное движение теряется.
    if (d < kOdometerMinStepM) return;
    _lastDistancePosition = p;
    // Скачок GPS: сбрасываем опору, но не считаем.
    if (d >= kOdometerMaxStepM) return;

    _tripDistanceMeters += d;
    _pendingDistanceMeters += d;
    _pendingDirty = true;

    FlutterForegroundTask.sendDataToMain("TRIP:$_tripDistanceMeters");
    AchievementService.addDistanceMeters(d);
    unawaited(_checkAndSyncDistance());
  }

  Future<void> _persistPending() async {
    if (!_pendingDirty) return;
    _pendingDirty = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(kKeyPendingDistanceMeters, _pendingDistanceMeters);
  }

  Future<void> _checkAndSyncDistance({bool force = false}) async {
    if (_syncFuture != null) {
      if (!force) return;
      await _syncFuture; // не отправляем те же метры дважды
    }
    final now = DateTime.now();
    if (!force && now.isBefore(_syncBackoffUntil)) return;
    if (_pendingDistanceMeters <= 0) return;

    final elapsedSec = now.difference(_lastDistanceSync).inSeconds;
    final due = force ||
        _pendingDistanceMeters >= kDistanceBatchBackgroundM ||
        (elapsedSec >= 20 && _pendingDistanceMeters >= 5.0);
    if (!due) return;

    final f = _doSync(_pendingDistanceMeters, now);
    _syncFuture = f;
    try {
      await f;
    } finally {
      _syncFuture = null;
    }
  }

  Future<void> _doSync(double meters, DateTime now) async {
    _lastDistanceSync = now;
    bool ok = false;
    try {
      ok = await ApiService.sendDistance(meters);
    } catch (_) {}

    if (ok) {
      _pendingDistanceMeters =
          (_pendingDistanceMeters - meters).clamp(0.0, double.infinity);
      _pendingDirty = true;
      await _persistPending();
      FlutterForegroundTask.sendDataToMain(
        "✅ Пробег сохранён: +${meters.toStringAsFixed(0)} м",
      );
    } else {
      _syncBackoffUntil = DateTime.now().add(const Duration(seconds: 15));
      _pendingDirty = true;
      await _persistPending();
    }
  }

  // ======================= Акселерометр =======================

  void _onAccel(AccelerometerEvent e) {
    final t = _clock.elapsedMilliseconds;
    final s = _gravity.update(e.x, e.y, e.z, _clock.elapsedMicroseconds);
    if (s == null || t < _warmupMs) return;
    _processSample(t, s.vertical, s.horizontal);
  }

  void _processSample(int t, double v, double h) {
    _feedRoughBins(t, v);

    if (_win == null) {
      if (t < _blockedUntil) return;
      final fix = _freshFix(t, 3000);
      if (fix == null ||
          fix.speedKmh < kMinDefectSpeedKmh ||
          fix.pos.accuracy > 40) {
        return;
      }
      final thr = bumpThresholdFor(fix.speedKmh) * (t < _roughUntil ? 1.5 : 1.0);
      if (v.abs() <= thr) return;
      _win = [_Sample(t, v, h)];
      _winStartT = t;
      _winFix = fix;
      _winGyroPeak = 0;
      return;
    }

    _win!.add(_Sample(t, v, h));
    if (t - _winStartT >= _windowMs) {
      final w = _win!;
      final fix = _winFix!;
      final gyro = _winGyroPeak;
      _win = null;
      _winFix = null;
      _blockedUntil = t + _postEventBlockMs;
      _classifyWindow(w, fix, gyro);
    }
  }

  /// Ширина одного импульса вокруг пика (мс): до тех пор, пока |v| не упадёт ниже уровня дольше _pulseGapMs.
  /// Удары передней и задней оси — разные импульсы, поэтому в ширину они не складываются.
  int _pulseWidthMs(List<_Sample> w, int peakIdx, double level) {
    int lo = peakIdx;
    int hi = peakIdx;
    for (int i = peakIdx - 1; i >= 0; i--) {
      if (w[i].v.abs() >= level) {
        lo = i;
      } else if (w[lo].t - w[i].t > _pulseGapMs) {
        break;
      }
    }
    for (int i = peakIdx + 1; i < w.length; i++) {
      if (w[i].v.abs() >= level) {
        hi = i;
      } else if (w[i].t - w[hi].t > _pulseGapMs) {
        break;
      }
    }
    return w[hi].t - w[lo].t;
  }

  // ---- Классификация удара ----
  void _classifyWindow(List<_Sample> w, _Fix fix, double gyroPeak) {
    double peak = 0, hPeak = 0;
    int peakIdx = 0;
    for (int i = 0; i < w.length; i++) {
      if (w[i].v.abs() > peak) {
        peak = w[i].v.abs();
        peakIdx = i;
      }
      if (w[i].h > hPeak) hPeak = w[i].h;
    }

    // Горизонталь доминирует: торможение / манёвр.
    if (hPeak > peak) {
      _log("↩️ Манёвр/торможение (игнор)");
      return;
    }
    // Телефон взяли в руки или уронили.
    if (gyroPeak > _gyroRejectRadS) {
      _log("↩️ Резкое вращение телефона (игнор)");
      return;
    }

    // Лежачий полицейский — один широкий импульс. Ширина в метрах пути, а не в миллисекундах:
    // на 25 км/ч оба удара оси ямы идут с задержкой около 0.4 с и по времени похожи на бугор.
    final pulseMs = _pulseWidthMs(w, peakIdx, peak * 0.5);
    final pulseM = pulseMs / 1000.0 * fix.speedKmh / 3.6;

    // Торможение перед препятствием: скорость 3–6 с назад заметно выше.
    final tStart = w.first.t;
    double before = 0;
    for (final s in _speedHist) {
      if (s.t >= tStart - 6000 && s.t <= tStart - 3000 && s.kmh > before) {
        before = s.kmh;
      }
    }
    final braked = before - fix.speedKmh >= 8 && fix.speedKmh < 0.75 * before;

    if (pulseM >= kSpeedBumpPulseM || (braked && pulseM >= kBrakedPulseM)) {
      _log("⚠️ Лежачий полицейский (игнор)");
      return;
    }

    final peakWall = _clockOriginWallMs + w[peakIdx].t;
    final at = _positionAt(peakWall);

    _emitDefect(
      type: 'pothole',
      lat: at.lat,
      lon: at.lon,
      speedKmh: fix.speedKmh,
      force: peak,
      severity: potholeSeverity(peak, fix.speedKmh),
      eventMs: peakWall,
      headingDeg: at.course,
      accuracyM: fix.pos.accuracy,
      trajectory: const [],
    );
  }

  // ---- Плохая дорога по RMS ----
  void _feedRoughBins(int t, double v) {
    _binSumSq += v * v;
    _binCount++;
    if (t - _binStartT < 500) return;

    final rms = _binCount > 0 ? sqrt(_binSumSq / _binCount) : 0.0;
    _binSumSq = 0;
    _binCount = 0;
    _binStartT = t;
    _bins.add(rms);
    if (_bins.length > 5) _bins.removeAt(0);
    _evaluateRoughRoad(t);
  }

  void _evaluateRoughRoad(int t) {
    if (t < _roughUntil || _bins.length < 5) return;
    final high = _bins.where((r) => r > kRoughRmsThresholdMs2).toList();
    if (high.length < 4) return;

    final fix = _freshFix(t, 3000);
    if (fix == null ||
        fix.pos.accuracy > 40 ||
        fix.speedKmh < kMinDefectSpeedKmh ||
        fix.speedKmh > _roughMaxSpeedKmh) {
      return; // блокировку не ставим: условия просто не выполнены
    }

    final meanRms = high.reduce((a, b) => a + b) / high.length;
    _roughUntil = t + _roughCooldownMs;
    _bins.clear();

    _emitDefect(
      type: 'rough_road',
      lat: fix.pos.latitude,
      lon: fix.pos.longitude,
      speedKmh: fix.speedKmh,
      force: meanRms * _roughForceScale,
      severity: severityFromRatio(meanRms / kRoughRmsThresholdMs2),
      eventMs: DateTime.now().millisecondsSinceEpoch,
      accuracyM: fix.pos.accuracy,
      trajectory: _roughTrack(fix.wallMs),
    );
  }

  /// Точки трека за последние секунды: весь буфер (10 фиксов) уходил далеко за участок тряски,
  /// и линия на карте рисовалась там, где тряски не было.
  List<Map<String, dynamic>> _roughTrack(int fixWallMs) {
    final cutoff = fixWallMs / 1000.0 - _roughTrackSec;
    return _trajectoryBuffer
        .where((p) => p.timestamp >= cutoff)
        .map((p) => p.toJson())
        .toList();
  }

  (double, double) _project(double lat, double lon, double headingDeg, double distM) {
    const r = 6371000.0;
    final br = headingDeg * pi / 180;
    final la = lat * pi / 180;
    final lo = lon * pi / 180;
    final dr = distM / r;
    final la2 = asin(sin(la) * cos(dr) + cos(la) * sin(dr) * cos(br));
    final lo2 = lo +
        atan2(sin(br) * sin(dr) * cos(la), cos(dr) - sin(la) * sin(la2));
    return (la2 * 180 / pi, lo2 * 180 / pi);
  }

  // ======================= Отправка и очередь =======================

  void _emitDefect({
    required String type,
    required double lat,
    required double lon,
    required double speedKmh,
    required double force,
    required int severity,
    required int eventMs,
    required List<Map<String, dynamic>> trajectory,
    double? headingDeg,
    double? accuracyM,
  }) {
    final seg = (_tripDistanceMeters / 100).floor();
    if (severity > 1 && severity > (_segSeverity[seg] ?? 1)) _segSeverity[seg] = severity;

    _log("⚡ $type (${force.toStringAsFixed(1)}). Отправка...");

    final ev = <String, dynamic>{
      'type': type,
      'lat': lat,
      'lon': lon,
      'speed': speedKmh,
      'force': force,
      'traj': trajectory,
      'hdg': headingDeg,
      'acc': accuracyM,
      'ts': eventMs,
      'id': '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 31)}',
      'attempts': 0,
    };
    unawaited(_deliver(ev));
  }

  Future<DefectSendResult> _send(Map<String, dynamic> ev) {
    return ApiService.sendDefectStatus(
      eventTimeMs: ev['ts'] as int,
      clientEventId: ev['id'] as String,
      lat: (ev['lat'] as num).toDouble(),
      lon: (ev['lon'] as num).toDouble(),
      speed: (ev['speed'] as num).toDouble(),
      force: (ev['force'] as num).toDouble(),
      defectType: ev['type'] as String,
      headingDeg: (ev['hdg'] as num?)?.toDouble(),
      accuracyM: (ev['acc'] as num?)?.toDouble(),
      trajectory: (ev['traj'] as List)
          .map((x) => Map<String, dynamic>.from(x as Map))
          .toList(),
    );
  }

  // 4xx (кроме 401/408/429) повторять бессмысленно: сервер отклонил данные.
  bool _isPermanent(int s) =>
      s >= 400 && s < 500 && s != 401 && s != 408 && s != 429;

  void _onDelivered(DefectSendResult res) {
    if (res.duplicate) {
      _log("↩️ Эта яма уже записана (повтор)");
      return;
    }
    _tripDefectsCount++;
    _log("✅ УСПЕХ! Данные на сервере.");
  }

  Future<void> _deliver(Map<String, dynamic> ev) async {
    DefectSendResult res = const DefectSendResult(0);
    try {
      res = await _send(ev);
    } catch (_) {}
    if (res.status == 200) {
      _onDelivered(res);
    } else if (_isPermanent(res.status)) {
      _log("⚠️ Сервер отклонил запись (${res.status})");
    } else {
      _log("❌ Ошибка сети/сервера. В очереди.");
      _queue.add(ev);
      if (_queue.length > _maxQueue) _queue.removeAt(0);
      await _saveQueue();
    }
  }

  void _loadQueue(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_kQueueKey);
      if (raw == null || raw.isEmpty) return;
      _queue = (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      _queue = [];
    }
  }

  Future<void> _saveQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kQueueKey, jsonEncode(_queue));
  }

  Future<void> _flushQueue() async {
    if (_flushing || _queue.isEmpty) return;
    _flushing = true;
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      _queue.removeWhere((e) => nowMs - (e['ts'] as int) > 24 * 3600 * 1000);
      for (int i = 0; i < 5 && _queue.isNotEmpty; i++) {
        final ev = _queue.first;
        DefectSendResult res = const DefectSendResult(0);
        try {
          res = await _send(ev);
        } catch (_) {}

        // remove(ev), а не removeAt(0): за время await _deliver мог вытеснить первый элемент.
        if (res.status == 200) {
          _queue.remove(ev);
          _onDelivered(res);
        } else if (_isPermanent(res.status)) {
          _queue.remove(ev);
        } else {
          // Нет сети (статус 0) — не попытка: иначе тоннель в 30 с стирал бы очередь, рассчитанную на сутки.
          if (res.status != 0) ev['attempts'] = (ev['attempts'] as int) + 1;
          if ((ev['attempts'] as int) >= 5) _queue.remove(ev);
          break;
        }
      }
      await _saveQueue();
    } finally {
      _flushing = false;
    }
  }

  void _log(String msg) => FlutterForegroundTask.sendDataToMain(msg);

  // ======================= Жизненный цикл =======================

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_persistPending());
    unawaited(_checkAndSyncDistance());
    unawaited(_flushQueue());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTaskDestroyed) async {
    await _accelSubscription?.cancel();
    await _gyroSubscription?.cancel();
    await _positionSubscription?.cancel();

    try {
      await _tripStart?.timeout(const Duration(seconds: 3));
    } catch (_) {}

    if (_currentTripId != null && _currentTripId! > 0) {
      // Доли — по длине дороги: сегменты по 100 м, а не по числу ударов.
      final segs = max(1, (_tripDistanceMeters / 100).ceil());
      final hard = _segSeverity.values.where((s) => s == 3).length;
      final med = _segSeverity.values.where((s) => s == 2).length;
      final hardRatio = (hard / segs).clamp(0.0, 1.0);
      final medRatio = (med / segs).clamp(0.0, 1.0 - hardRatio);
      final smoothRatio = (1.0 - hardRatio - medRatio).clamp(0.0, 1.0);

      try {
        await ApiService.finishTrip(
          tripId: _currentTripId!,
          distanceMeters: _tripDistanceMeters,
          defectsCount: _tripDefectsCount,
          smoothRatio: smoothRatio,
          mediumRatio: medRatio,
          hardRatio: hardRatio,
        ).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }

    await _checkAndSyncDistance(force: true);
    _pendingDirty = true;
    await _persistPending();
    await _flushQueue();
    FlutterForegroundTask.sendDataToMain("🛑 ФОН: Мониторинг остановлен");
  }
}
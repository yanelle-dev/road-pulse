import 'dart:async';
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

class SensorTaskHandler extends TaskHandler {
  static const double bumpThreshold = 7.0;

  StreamSubscription? _accelSubscription;
  StreamSubscription? _positionSubscription;

  bool _isMonitoring = true;

  final double _zPeakThreshold = 5.0;
  DateTime? _zPeakStartTime;

  final double _yPeakThreshold = 4.0;
  final List<DateTime> _yPeaks = [];
  bool _isRoughRoadActive = false;

  final List<TrajectoryPoint> _trajectoryBuffer = [];

  Position? _lastDistancePosition;
  double _pendingDistanceMeters = 0.0;
  double _tripDistanceMeters = 0.0;
  DateTime _lastDistanceSync = DateTime.now();

  int? _currentTripId;
  int _tripDefectsCount = 0;
  int _tripS2Count = 0;
  int _tripS3Count = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    FlutterForegroundTask.sendDataToMain("🟢 ФОН: Мониторинг запущен...");

    final prefs = await SharedPreferences.getInstance();
    _pendingDistanceMeters = prefs.getDouble(kKeyPendingDistanceMeters) ?? 0.0;
    _tripDistanceMeters = 0.0;
    FlutterForegroundTask.sendDataToMain("TRIP:0.0");

    _currentTripId = await ApiService.startTrip();
    _tripDefectsCount = 0;
    _tripS2Count = 0;
    _tripS3Count = 0;

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1,
      ),
    ).listen(_updateTrajectoryAndDistance);

    _accelSubscription = userAccelerometerEventStream().listen((event) async {
      if (!_isMonitoring) return;

      if (_isSpeedBump(event.z)) return;

      await _detectRoughRoad(event.y);
      await _detectPothole(event);
    });

    if (_pendingDistanceMeters > 0) {
      _checkAndSyncDistance();
    }
  }

  void _updateTrajectoryAndDistance(Position position) async {
    final point = TrajectoryPoint(
      position.latitude,
      position.longitude,
      DateTime.now().millisecondsSinceEpoch / 1000.0,
    );
    _trajectoryBuffer.add(point);
    if (_trajectoryBuffer.length > 10) {
      _trajectoryBuffer.removeAt(0);
    }

    if (position.accuracy > kOdometerMaxAccuracyM) return;

    if (_lastDistancePosition != null) {
      final distanceM = Geolocator.distanceBetween(
        _lastDistancePosition!.latitude,
        _lastDistancePosition!.longitude,
        position.latitude,
        position.longitude,
      );

      if (distanceM >= kOdometerMinStepM && distanceM < kOdometerMaxStepM) {
        _tripDistanceMeters += distanceM;
        _pendingDistanceMeters += distanceM;

        FlutterForegroundTask.sendDataToMain("TRIP:$_tripDistanceMeters");
        AchievementService.addDistanceMeters(distanceM);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble(kKeyPendingDistanceMeters, _pendingDistanceMeters);

        _checkAndSyncDistance();
      }
    }
    _lastDistancePosition = position;
  }

  Future<void> _checkAndSyncDistance({bool force = false}) async {
    final now = DateTime.now();
    final elapsedSec = now.difference(_lastDistanceSync).inSeconds;

    if (force ||
        _pendingDistanceMeters >= kDistanceBatchBackgroundM ||
        (elapsedSec >= 20 && _pendingDistanceMeters >= 5.0)) {
      if (_pendingDistanceMeters <= 0) return;

      final metersToSend = _pendingDistanceMeters;
      _lastDistanceSync = now;

      final success = await ApiService.sendDistance(metersToSend);
      final prefs = await SharedPreferences.getInstance();

      if (success) {
        _pendingDistanceMeters = (_pendingDistanceMeters - metersToSend).clamp(0.0, double.infinity);
        await prefs.setDouble(kKeyPendingDistanceMeters, _pendingDistanceMeters);
        FlutterForegroundTask.sendDataToMain(
          "✅ Пробег сохранён: +${metersToSend.toStringAsFixed(0)} м",
        );
      } else {
        await prefs.setDouble(kKeyPendingDistanceMeters, _pendingDistanceMeters);
      }
    }
  }

  bool _isSpeedBump(double zForce) {
    if (zForce.abs() > _zPeakThreshold) {
      _zPeakStartTime ??= DateTime.now();
      return true;
    } else if (_zPeakStartTime != null) {
      final duration = DateTime.now().difference(_zPeakStartTime!);
      _zPeakStartTime = null;

      if (duration.inMilliseconds < 300) {
        FlutterForegroundTask.sendDataToMain("⚠️ Лежачий полицейский (игнор)");
        _pauseMonitoring(500);
        return true;
      }
    }
    return false;
  }

  Future<void> _detectRoughRoad(double yForce) async {
    if (_isRoughRoadActive || yForce.abs() <= _yPeakThreshold) return;

    final now = DateTime.now();
    _yPeaks.add(now);
    _yPeaks.removeWhere((t) => now.difference(t).inSeconds > 5);

    if (_yPeaks.length > 4) {
      _isRoughRoadActive = true;
      await _sendDefectData(
        defectType: 'rough_road',
        minSpeed: kMinDefectSpeedKmh,
        maxSpeed: 40.0,
        force: _yPeaks.length * 2.0,
      );

      Future.delayed(const Duration(seconds: 5), () {
        _isRoughRoadActive = false;
        _yPeaks.clear();
      });
    }
  }

  Future<void> _detectPothole(UserAccelerometerEvent event) async {
    if (_isRoughRoadActive) return;

    double force = sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    if (force > bumpThreshold) {
      _pauseMonitoring(2000);
      await _sendDefectData(
        defectType: 'pothole',
        minSpeed: kMinDefectSpeedKmh,
        maxSpeed: double.infinity,
        force: force,
      );
    }
  }

  Future<void> _sendDefectData({
    required String defectType,
    required double minSpeed,
    required double maxSpeed,
    required double force,
  }) async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      double speedKmh = position.speed * 3.6;

      if (speedKmh < minSpeed) {
        FlutterForegroundTask.sendDataToMain(
          "⚠️ Удар, скорость мала: ${speedKmh.toStringAsFixed(1)} км/ч",
        );
        return;
      }
      if (speedKmh > maxSpeed) {
        return;
      }

      FlutterForegroundTask.sendDataToMain(
        "⚡ $defectType (${force.toStringAsFixed(1)}). Отправка...",
      );

      bool success = await ApiService.sendDefect(
        lat: position.latitude,
        lon: position.longitude,
        speed: speedKmh,
        force: force,
        defectType: defectType,
        trajectory: _trajectoryBuffer.map((p) => p.toJson()).toList(),
      );

      if (success) {
        FlutterForegroundTask.sendDataToMain("✅ УСПЕХ! Данные на сервере.");
        _tripDefectsCount++;
        if (force > kSeverityHard) {
          _tripS3Count++;
        } else if (force > kSeverityMedium) {
          _tripS2Count++;
        }
      } else {
        FlutterForegroundTask.sendDataToMain("❌ Ошибка сети/сервера.");
      }
    } catch (e) {
      FlutterForegroundTask.sendDataToMain("❌ Ошибка GPS: $e");
    }
  }

  void _pauseMonitoring(int milliseconds) {
    _isMonitoring = false;
    Future.delayed(
      Duration(milliseconds: milliseconds),
      () => _isMonitoring = true,
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _checkAndSyncDistance();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTaskDestroyed) async {
    if (_currentTripId != null && _currentTripId! > 0) {
      final total = _tripDefectsCount;
      double hardRatio = total > 0 ? (_tripS3Count / total).clamp(0.0, 0.4) : 0.05;
      double medRatio = total > 0 ? (_tripS2Count / total).clamp(0.0, 0.5) : 0.15;
      double smoothRatio = (1.0 - hardRatio - medRatio).clamp(0.2, 1.0);

      await ApiService.finishTrip(
        tripId: _currentTripId!,
        distanceMeters: _tripDistanceMeters,
        defectsCount: _tripDefectsCount,
        smoothRatio: smoothRatio,
        mediumRatio: medRatio,
        hardRatio: hardRatio,
      );
    }

    await _checkAndSyncDistance(force: true);
    await _accelSubscription?.cancel();
    await _positionSubscription?.cancel();
    FlutterForegroundTask.sendDataToMain("🛑 ФОН: Мониторинг остановлен");
  }
}
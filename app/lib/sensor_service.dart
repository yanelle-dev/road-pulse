import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'achievement_service.dart';
import 'api_service.dart';

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
  DateTime _lastDistanceSync = DateTime.now();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    FlutterForegroundTask.sendDataToMain("🟢 ФОН: Мониторинг запущен...");

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
  }

  void _updateTrajectoryAndDistance(Position position) {
    final point = TrajectoryPoint(
      position.latitude,
      position.longitude,
      DateTime.now().millisecondsSinceEpoch / 1000.0,
    );
    _trajectoryBuffer.add(point);
    if (_trajectoryBuffer.length > 10) {
      _trajectoryBuffer.removeAt(0);
    }

    // Порог точности 80 м для пешеходов и машин
    if (position.accuracy > 80.0) return;

    if (_lastDistancePosition != null) {
      final distanceM = Geolocator.distanceBetween(
        _lastDistancePosition!.latitude,
        _lastDistancePosition!.longitude,
        position.latitude,
        position.longitude,
      );

      // Шаг пешехода фиксируется от 0.6 метра
      if (distanceM >= 0.6 && distanceM < 300.0) {
        _pendingDistanceMeters += distanceM;
        AchievementService.addDistanceMeters(distanceM);
        _checkAndSyncDistance();
      }
    }
    _lastDistancePosition = position;
  }

  Future<void> _checkAndSyncDistance({bool force = false}) async {
    final now = DateTime.now();
    final elapsedSec = now.difference(_lastDistanceSync).inSeconds;

    if (force ||
        _pendingDistanceMeters >= 25.0 ||
        (elapsedSec >= 20 && _pendingDistanceMeters >= 5.0)) {
      if (_pendingDistanceMeters <= 0) return;

      final metersToSend = _pendingDistanceMeters;
      _pendingDistanceMeters = 0.0;
      _lastDistanceSync = now;

      final success = await ApiService.sendDistance(metersToSend);
      if (success) {
        FlutterForegroundTask.sendDataToMain(
          "✅ Пробег сохранён: +${metersToSend.toStringAsFixed(0)} м",
        );
      } else {
        _pendingDistanceMeters += metersToSend;
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
        minSpeed: 20.0,
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
        minSpeed: 20.0,
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
    await _checkAndSyncDistance(force: true);
    await _accelSubscription?.cancel();
    await _positionSubscription?.cancel();
    FlutterForegroundTask.sendDataToMain("🛑 ФОН: Мониторинг остановлен");
  }
}
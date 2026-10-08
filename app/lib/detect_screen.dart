import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'achievement_service.dart';
import 'api_service.dart';
import 'app_theme.dart';
import 'sensor_service.dart';
import 'widgets/onboarding_panel.dart';

class DetectScreen extends StatefulWidget {
  const DetectScreen({super.key});

  @override
  State<DetectScreen> createState() => _DetectScreenState();
}

class _DetectScreenState extends State<DetectScreen> {
  bool _isActive = false;

  StreamSubscription<Position>? _positionStream;
  StreamSubscription<UserAccelerometerEvent>? _accelStream;

  double _currentSpeed = 0.0;
  double _tripDistanceMeters = 0.0;
  double _pendingSyncMeters = 0.0;
  Position? _lastPos;

  final int _maxDataPoints = 60;
  List<double> _accelData = [];

  @override
  void initState() {
    super.initState();
    _accelData = List.generate(_maxDataPoints, (_) => 0.0);

    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPermissionsAndStart();
    });

    _initSensors();
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    _positionStream?.cancel();
    _accelStream?.cancel();
    super.dispose();
  }

  void _onReceiveTaskData(Object data) {
    if (data is String) {
      ApiService.addLog(data);
    }
  }

  void _initSensors() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1, // Чувствительность 1 метр
      ),
    ).listen((Position position) {
      if (!mounted) return;

      final gpsSpeedKmh = (position.speed * 3.6).clamp(0.0, 999.0);

      if (_isActive && _lastPos != null && position.accuracy <= 80.0) {
        final distanceM = Geolocator.distanceBetween(
          _lastPos!.latitude,
          _lastPos!.longitude,
          position.latitude,
          position.longitude,
        );

        // Фиксация любого реального шага (от 0.6 м до 300 м)
        if (distanceM >= 0.6 && distanceM < 300.0) {
          _tripDistanceMeters += distanceM;
          _pendingSyncMeters += distanceM;

          AchievementService.addDistanceMeters(distanceM);

          // Логирование в журнал каждые 15 м
          if (_pendingSyncMeters >= 15.0) {
            final toSend = _pendingSyncMeters;
            _pendingSyncMeters = 0.0;
            ApiService.sendDistance(toSend);
            ApiService.addLog("🟢 Шаг зафиксирован: +${toSend.toStringAsFixed(0)} м (всего: ${_tripDistanceMeters.toStringAsFixed(0)} м)");
          }
        }
      }
      _lastPos = position;

      setState(() {
        _currentSpeed = gpsSpeedKmh;
      });
    });

    _accelStream = userAccelerometerEventStream().listen((
      UserAccelerometerEvent event,
    ) {
      if (mounted) {
        setState(() {
          _accelData.removeAt(0);
          _accelData.add(event.z);
        });
      }
    });
  }

  Future<void> _checkPermissionsAndStart() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      await _initForegroundTask();
      if (!_isActive) {
        _toggleTracking();
      }
    } else {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OnboardingPanel(
            onAllow: () async {
              await _initForegroundTask();
              if (!_isActive) {
                _toggleTracking();
              }
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
        ),
      );
    }
  }

  Future<void> _initForegroundTask() async {
    await Geolocator.requestPermission();
    await FlutterForegroundTask.requestNotificationPermission();
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'road_pulse_tracking',
        channelName: 'Road Pulse Tracking',
        channelDescription: 'Сканирование дорожного полотна работает в фоне',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  void _toggleTracking() async {
    try {
      if (_isActive) {
        ApiService.addLog("Остановка службы мониторинга");
        if (_pendingSyncMeters > 0) {
          final toSend = _pendingSyncMeters;
          _pendingSyncMeters = 0.0;
          await ApiService.sendDistance(toSend);
        }
        await FlutterForegroundTask.stopService();
        setState(() => _isActive = false);
      } else {
        ApiService.addLog("🟢 Мониторинг запущен. Одометр активен");
        if (await FlutterForegroundTask.isRunningService) {
          await FlutterForegroundTask.stopService();
        }
        await FlutterForegroundTask.startService(
          notificationTitle: 'Road Pulse',
          notificationText: 'Служба записи дорожного покрытия активна',
          callback: startCallback,
        );
        setState(() {
          _isActive = true;
          _tripDistanceMeters = 0.0;
          _pendingSyncMeters = 0.0;
          _lastPos = null;
        });
      }
    } catch (e) {
      ApiService.addLog("Ошибка службы: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return WithForegroundTask(
      child: Scaffold(
        backgroundColor: colors.voidBg,
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(colors),
                _buildSpeedometer(colors),
                _buildOdometerCard(colors),
                _buildGateBanner(colors),
                _buildScope(colors),
                _buildTerminal(colors),
                _buildActionButton(colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(PolotnoColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Запись",
            style: TextStyle(
              fontFamily: AppTheme.fontDisplay,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: colors.ink,
              letterSpacing: -0.8,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _isActive ? colors.s1Soft : colors.surf2,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _isActive ? colors.s1 : colors.ink3,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  _isActive ? "ПИШУ ДОРОГУ" : "НА ПАУЗЕ",
                  style: TextStyle(
                    fontFamily: AppTheme.fontUi,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: _isActive ? colors.s1 : colors.ink3,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedometer(PolotnoColors colors) {
    final int speedInt = _currentSpeed.round();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Center(
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                "$speedInt",
                style: TextStyle(
                  fontFamily: AppTheme.fontDisplay,
                  fontSize: 110,
                  fontWeight: FontWeight.w800,
                  color: colors.ink,
                  height: 0.85,
                  letterSpacing: -6.0,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "КМ/Ч · ТЕКУЩАЯ СКОРОСТЬ",
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.5,
                color: colors.ink3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOdometerCard(PolotnoColors colors) {
    final kmStr = (_tripDistanceMeters / 1000.0).toStringAsFixed(2);
    final mStr = _tripDistanceMeters.toStringAsFixed(0);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surf,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.edge2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.route_rounded, color: colors.mark, size: 20),
              const SizedBox(width: 10),
              Text(
                "ПРОБЕГ ЗА ПОЕЗДКУ",
                style: TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                  color: colors.ink2,
                ),
              ),
            ],
          ),
          Text(
            "$kmStr км ($mStr м)",
            style: TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _isActive ? colors.s1 : colors.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGateBanner(PolotnoColors colors) {
    final bool isAboveThreshold = _currentSpeed >= 20.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: isAboveThreshold ? colors.s1Soft : colors.surf,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAboveThreshold ? colors.s1Soft : colors.edge2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isAboveThreshold
                ? Icons.check_circle_outline_rounded
                : Icons.info_outline_rounded,
            color: isAboveThreshold ? colors.s1 : colors.ink3,
            size: 18,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 12.0,
                  color: colors.ink2,
                  height: 1.4,
                ),
                children: isAboveThreshold
                    ? [
                        const TextSpan(text: "Скорость выше 20 км/ч — "),
                        TextSpan(
                          text: "удары ям записываются",
                          style: TextStyle(
                            color: colors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const TextSpan(text: "."),
                      ]
                    : [
                        const TextSpan(
                          text:
                              "Пробег пишется на любой скорости (пешком и авто). Запись ударов полотна включится от 20 км/ч.",
                        ),
                      ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScope(PolotnoColors colors) {
    final double currentZ = _accelData.isNotEmpty ? _accelData.last : 0.0;

    return Container(
      height: 140,
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surf,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.edge2),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "ВИБРАЦИЯ · ОСЬ Z",
                style: TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.4,
                  color: colors.ink3,
                ),
              ),
              Text(
                "${currentZ.abs().toStringAsFixed(1)} g",
                style: TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: currentZ.abs() >= 7.0 ? colors.s3 : colors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: PolotnoScopePainter(
                data: _accelData,
                lineColor: colors.s1,
                gridColor: colors.edge,
                alertColor: colors.s3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminal(PolotnoColors colors) {
    return Container(
      height: 170,
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.term,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.edge2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.terminal_rounded, size: 14, color: colors.ink3),
              const SizedBox(width: 8),
              Text(
                "ЖУРНАЛ",
                style: TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.5,
                  color: colors.ink3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: ApiService.logs,
              builder: (context, logs, _) {
                if (logs.isEmpty) {
                  return Center(
                    child: Text(
                      "Ожидание первого движения...",
                      style: TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 11,
                        color: colors.ink3,
                      ),
                    ),
                  );
                }

                final displayLogs = logs.reversed.take(6).toList();

                return ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: displayLogs.length,
                  itemBuilder: (context, index) {
                    final dynamic entry = displayLogs[index];
                    String time = '';
                    String message = '';
                    String kind = '';

                    if (entry is String) {
                      message = entry;
                    } else {
                      final dynamic d = entry;
                      try {
                        final t = d.time;
                        if (t != null) time = t.toString();
                      } catch (_) {}
                      try {
                        final m = d.message;
                        if (m != null) message = m.toString();
                      } catch (_) {}
                      if (message.isEmpty) message = entry.toString();
                      try {
                        final k = d.kind ?? d.level;
                        if (k != null) kind = k.toString().toLowerCase();
                      } catch (_) {}
                    }

                    Color textColor = const Color(0xFF98A1A8);
                    final lowerMsg = message.toLowerCase();
                    if (kind == 'hit' || lowerMsg.contains('удар')) {
                      textColor = colors.s3;
                    } else if (kind == 'ok' || lowerMsg.contains('зафиксирован') || lowerMsg.contains('пройдено') || lowerMsg.contains('актив')) {
                      textColor = colors.s1;
                    } else if (kind == 'warn' || lowerMsg.contains('пауз')) {
                      textColor = colors.mark;
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 5.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (time.isNotEmpty) ...[
                            SizedBox(
                              width: 42,
                              child: Text(
                                time,
                                style: TextStyle(
                                  fontFamily: AppTheme.fontMono,
                                  fontSize: 10.5,
                                  color: colors.ink3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              message,
                              style: TextStyle(
                                fontFamily: AppTheme.fontMono,
                                fontSize: 10.5,
                                color: textColor,
                                height: 1.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(PolotnoColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          backgroundColor: _isActive ? colors.s3 : colors.mark,
          foregroundColor: _isActive ? Colors.white : colors.onMark,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        onPressed: _toggleTracking,
        child: Text(
          _isActive ? "Остановить запись" : "Запустить запись",
          style: TextStyle(
            fontFamily: AppTheme.fontUi,
            fontSize: 16.0,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
      ),
    );
  }
}

class PolotnoScopePainter extends CustomPainter {
  final List<double> data;
  final Color lineColor;
  final Color gridColor;
  final Color alertColor;

  PolotnoScopePainter({
    required this.data,
    required this.lineColor,
    required this.gridColor,
    required this.alertColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double midY = size.height / 2;
    const double maxG = 10.0;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final double yThresholdTop = midY - (7.0 / maxG) * (midY - 4);
    final double yThresholdBottom = midY + (7.0 / maxG) * (midY - 4);

    _drawDashedLine(canvas, Offset(0, yThresholdTop), Offset(size.width, yThresholdTop), gridPaint);
    _drawDashedLine(canvas, Offset(0, yThresholdBottom), Offset(size.width, yThresholdBottom), gridPaint);

    if (data.length < 2) return;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    final double stepX = size.width / (data.length - 1);

    for (int i = 0; i < data.length; i++) {
      final double clamped = data[i].clamp(-maxG, maxG);
      final double y = midY - (clamped / maxG) * (midY - 6);

      if (i == 0) {
        path.moveTo(0, y);
      } else {
        path.lineTo(i * stepX, y);
      }
    }

    canvas.drawPath(path, linePaint);

    final double lastVal = data.last;
    if (lastVal.abs() >= 4.0) {
      final dotPaint = Paint()..color = alertColor;
      final double dotY = midY - (lastVal.clamp(-maxG, maxG) / maxG) * (midY - 6);
      canvas.drawCircle(Offset(size.width - 2, dotY), 4, dotPaint);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const double dashWidth = 4;
    const double dashSpace = 4;
    double startX = p1.dx;

    while (startX < p2.dx) {
      canvas.drawLine(
        Offset(startX, p1.dy),
        Offset((startX + dashWidth).clamp(p1.dx, p2.dx), p1.dy),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant PolotnoScopePainter oldDelegate) => true;
}
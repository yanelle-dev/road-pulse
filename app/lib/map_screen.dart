import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;

import 'api_service.dart';
import 'app_theme.dart';
import 'constants.dart';
import 'pothole_details_screen.dart';
import 'widgets/road_ribbon.dart';

class MapScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateToTab;

  const MapScreen({super.key, this.onNavigateToTab});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  List<dynamic> _bumps = [];
  LatLng? _myLocation;
  double _currentSpeedKmh = 0.0;
  bool _isServiceRunning = false;
  StreamSubscription<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    _loadBumps();
    _locateUser();
    _checkServiceStatus();
    _initSpeedListener();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _checkServiceStatus() async {
    final running = await FlutterForegroundTask.isRunningService;
    if (mounted) {
      setState(() => _isServiceRunning = running);
    }
  }

  void _initSpeedListener() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      ),
    ).listen((pos) {
      if (mounted) {
        setState(() {
          _myLocation = LatLng(pos.latitude, pos.longitude);
          _currentSpeedKmh = (pos.speed * 3.6).clamp(0.0, 999.0);
        });
      }
    });
  }

  Future<void> _locateUser() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (mounted) {
        setState(() {
          _myLocation = LatLng(pos.latitude, pos.longitude);
          _currentSpeedKmh = (pos.speed * 3.6).clamp(0.0, 999.0);
        });
        _mapController.move(_myLocation!, 15.0);
      }
    } catch (e) {
      debugPrint("Не удалось получить GPS: $e");
    }
  }

  Future<void> _loadBumps() async {
    try {
      final bumps = await ApiService.getBumps();
      if (mounted) {
        setState(() {
          _bumps = bumps;
        });
      }
    } catch (e) {
      debugPrint("Не удалось загрузить ямы: $e");
    }
  }

  List<Polyline> _buildPolylines(PolotnoColors colors) {
    final List<Polyline> polylines = [];

    for (final b in _bumps) {
      if (b['defect_type'] != 'rough_road') continue;

      final rawCoords = b['coordinates'];
      if (rawCoords is! List || rawCoords.length < 2) continue;

      final List<LatLng> points = [];
      for (final pt in rawCoords) {
        if (pt is List && pt.length >= 2) {
          final lat = (pt[0] as num).toDouble();
          final lon = (pt[1] as num).toDouble();
          points.add(LatLng(lat, lon));
        }
      }

      if (points.length < 2) continue;

      final double force = ((b['max_force'] ?? 0.0) as num).toDouble();
      final bool isConfirmed = b['is_confirmed'] ?? false;

      Color lineColor = colors.s1;
      if (force > kSeverityHard) {
        lineColor = colors.s3;
      } else if (force > kSeverityMedium) {
        lineColor = colors.s2;
      }

      polylines.add(
        Polyline(
          points: points,
          strokeWidth: isConfirmed ? 5.0 : 3.5,
          color: isConfirmed ? lineColor : lineColor.withValues(alpha: 0.65),
          borderColor: colors.asphalt,
          borderStrokeWidth: isConfirmed ? 1.5 : 0.0,
        ),
      );
    }

    return polylines;
  }

  List<CircleMarker> _buildCircles(PolotnoColors colors) {
    final List<CircleMarker> circles = [];

    for (final b in _bumps) {
      final bool isConfirmed = b['is_confirmed'] ?? false;
      if (!isConfirmed) continue;

      // Участки с геометрией линий уже отрисованы в PolylineLayer
      if (b['defect_type'] == 'rough_road' && (b['coordinates'] as List?)?.isNotEmpty == true) {
        continue;
      }

      final double force = (b['max_force'] ?? 0.0).toDouble();
      final double lat = (b['lat'] ?? b['latitude'] ?? 0.0).toDouble();
      final double lon = (b['lon'] ?? b['longitude'] ?? 0.0).toDouble();
      final LatLng point = LatLng(lat, lon);

      Color bumpColor = colors.s1;
      double radius = 10.0;

      if (force > kSeverityHard) {
        bumpColor = colors.s3;
        radius = 16.0;
      } else if (force > kSeverityMedium) {
        bumpColor = colors.s2;
        radius = 12.0;
      }

      circles.add(
        CircleMarker(
          point: point,
          color: bumpColor.withValues(alpha: 0.22),
          borderStrokeWidth: 0,
          useRadiusInMeter: true,
          radius: radius * 1.8,
        ),
      );

      circles.add(
        CircleMarker(
          point: point,
          color: bumpColor,
          borderStrokeWidth: 2,
          borderColor: colors.asphalt,
          useRadiusInMeter: true,
          radius: radius,
        ),
      );
    }

    return circles;
  }

  List<Marker> _buildMarkers(PolotnoColors colors) {
    final List<Marker> unconfirmedMarkers = [];

    for (final b in _bumps) {
      final bool isConfirmed = b['is_confirmed'] ?? false;
      if (isConfirmed) continue;

      if (b['defect_type'] == 'rough_road' && (b['coordinates'] as List?)?.isNotEmpty == true) {
        continue;
      }

      final double lat = (b['lat'] ?? b['latitude'] ?? 0.0).toDouble();
      final double lon = (b['lon'] ?? b['longitude'] ?? 0.0).toDouble();
      final LatLng point = LatLng(lat, lon);

      unconfirmedMarkers.add(
        Marker(
          point: point,
          width: 22,
          height: 22,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.ink3, width: 2),
            ),
          ),
        ),
      );
    }

    return unconfirmedMarkers;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colors.voidBg,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(55.751244, 37.618423),
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.roadpulse.app',
                tileBuilder: isDark ? darkModeTileBuilder : null,
              ),
              PolylineLayer(polylines: _buildPolylines(colors)),
              CircleLayer(circles: _buildCircles(colors)),
              MarkerLayer(
                markers: [
                  ..._buildMarkers(colors),
                  if (_myLocation != null)
                    Marker(
                      point: _myLocation!,
                      width: 36,
                      height: 36,
                      child: _buildUserLocationMarker(colors),
                    ),
                ],
              ),
            ],
          ),
          Positioned(top: 54, left: 16, child: _buildRecordCapsule(colors)),
          Positioned(
            top: 106,
            left: 16,
            right: 16,
            child: _buildSearchBar(colors),
          ),
          Positioned(
            top: 174,
            right: 16,
            child: _buildFloatingActionBtn(
              colors: colors,
              icon: Icons.my_location,
              iconColor: colors.markInk,
              onTap: () {
                _loadBumps();
                _locateUser();
                _checkServiceStatus();
              },
            ),
          ),
          Positioned(
            top: 228,
            right: 16,
            child: _buildFloatingActionBtn(
              colors: colors,
              icon: Icons.layers_outlined,
              iconColor: colors.ink2,
              onTap: () {},
            ),
          ),
          _buildDraggableSheet(colors),
        ],
      ),
    );
  }

  Widget _buildUserLocationMarker(PolotnoColors colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.mark,
        shape: BoxShape.circle,
        border: Border.all(color: colors.asphalt, width: 3.5),
        boxShadow: [
          BoxShadow(
            color: colors.mark.withValues(alpha: 0.45),
            blurRadius: 16,
            spreadRadius: 4,
          ),
        ],
      ),
    );
  }

  Widget _buildRecordCapsule(PolotnoColors colors) {
    final speed = _currentSpeedKmh.round();
    final isActive = _isServiceRunning;

    return GestureDetector(
      onTap: () => widget.onNavigateToTab?.call(2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: colors.glass,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: colors.edge),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isActive ? colors.s1 : colors.ink3,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isActive ? "ЗАПИСЬ" : "ПАУЗА",
                  style: TextStyle(
                    fontFamily: AppTheme.fontUi,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: colors.ink,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "$speed км/ч",
                  style: TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 11.5,
                    color: colors.ink2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(PolotnoColors colors) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: colors.glass,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.edge),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: colors.ink3, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Куда едем?",
                  style: TextStyle(
                    fontFamily: AppTheme.fontUi,
                    color: colors.ink3,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(Icons.mic_none_rounded, color: colors.ink3, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingActionBtn({
    required PolotnoColors colors,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colors.glass,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.edge),
            ),
            child: Icon(icon, color: iconColor, size: 21),
          ),
        ),
      ),
    );
  }

  Widget _buildDraggableSheet(PolotnoColors colors) {
    final int hardCount = _bumps.where((b) {
      final f = (b['max_force'] ?? 0.0).toDouble();
      return f > kSeverityHard;
    }).length;

    // Сортируем реальные дефекты по расстоянию от текущей позиции
    final List<Map<String, dynamic>> nearestBumps = [];
    if (_myLocation != null) {
      for (final b in _bumps) {
        final lat = (b['lat'] ?? b['latitude'] ?? 0.0).toDouble();
        final lon = (b['lon'] ?? b['longitude'] ?? 0.0).toDouble();
        final dist = Geolocator.distanceBetween(
          _myLocation!.latitude,
          _myLocation!.longitude,
          lat,
          lon,
        );
        nearestBumps.add({
          ...b,
          'calc_distance_m': dist,
        });
      }
      nearestBumps.sort((a, b) => (a['calc_distance_m'] as double).compareTo(b['calc_distance_m'] as double));
    }

    final displayDefects = nearestBumps.take(3).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.38,
      minChildSize: 0.22,
      maxChildSize: 0.85,
      snap: true,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.surf,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: colors.edge, width: 1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 40,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colors.edge,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    "Карта дефектов",
                    style: TextStyle(
                      fontFamily: AppTheme.fontDisplay,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                      letterSpacing: -0.8,
                    ),
                  ),
                  Text(
                    "ОБЗОР",
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.2,
                      color: colors.ink3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              RoadRibbon(
                height: 14,
                currentPosition: 0.2,
                segments: [
                  RibbonSegment(flex: 0.65, color: colors.s1),
                  RibbonSegment(flex: 0.20, color: colors.s2),
                  RibbonSegment(flex: 0.15, color: colors.s3),
                ],
              ),
              const SizedBox(height: 16),
              FutureBuilder<UserStats>(
                future: ApiService.getUserStats(),
                builder: (context, snap) {
                  final stats = snap.data ?? UserStats.empty();
                  return Row(
                    children: [
                      _buildStatPill(colors, "$hardCount", "ЖЁСТКИХ НА КАРТЕ", colors.s3),
                      const SizedBox(width: 8),
                      _buildStatPill(colors, stats.totalKm.toStringAsFixed(1), "КМ ЗАПИСАНО", colors.ink),
                      const SizedBox(width: 8),
                      _buildStatPill(colors, "${stats.rating}", "ОЧКОВ", colors.markInk),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Ближайшие дефекты",
                    style: TextStyle(
                      fontFamily: AppTheme.fontUi,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => widget.onNavigateToTab?.call(1),
                    child: Text(
                      "Все ${_bumps.length}",
                      style: TextStyle(
                        fontFamily: AppTheme.fontUi,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.markInk,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (displayDefects.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      _bumps.isEmpty ? "Данные загружаются..." : "Поблизости дефектов не обнаружено",
                      style: TextStyle(
                        fontFamily: AppTheme.fontUi,
                        fontSize: 13,
                        color: colors.ink3,
                      ),
                    ),
                  ),
                )
              else
                ...displayDefects.map((bump) {
                  final lat = (bump['lat'] ?? bump['latitude'] ?? 0.0).toDouble();
                  final lon = (bump['lon'] ?? bump['longitude'] ?? 0.0).toDouble();
                  final force = (bump['max_force'] ?? 0.0).toDouble();
                  final distM = (bump['calc_distance_m'] as double?) ?? 0.0;
                  final distStr = distM >= 1000 ? "${(distM / 1000).toStringAsFixed(1)} км" : "${distM.round()} м";
                  final confirms = bump['total_hits'] ?? bump['unique_users'] ?? 1;

                  final isHard = force > kSeverityHard;
                  final isMed = force > kSeverityMedium;

                  return _buildDefectRow(
                    colors: colors,
                    title: bump['defect_type'] == 'rough_road' ? "Неровная дорога" : "Дефект полотна",
                    coord: "${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}",
                    time: distStr,
                    levelText: isHard ? "ЖЁСТКО" : (isMed ? "ЗАМЕТНО" : "РОВНО"),
                    levelColor: isHard ? colors.s3 : (isMed ? colors.s2 : colors.s1),
                    levelBg: isHard ? colors.s3Soft : (isMed ? colors.s2Soft : colors.s1Soft),
                    confirms: confirms,
                    rawDefect: bump,
                  );
                }),
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  side: BorderSide(color: colors.edge),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  backgroundColor: colors.surf,
                ),
                onPressed: () => widget.onNavigateToTab?.call(1),
                child: Text(
                  "Открыть ленту дефектов",
                  style: TextStyle(
                    fontFamily: AppTheme.fontUi,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.ink,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatPill(
    PolotnoColors colors,
    String val,
    String label,
    Color valColor,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: colors.surf,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.edge2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              val,
              style: TextStyle(
                fontFamily: AppTheme.fontDisplay,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: valColor,
                letterSpacing: -0.8,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 8.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.8,
                color: colors.ink3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefectRow({
    required PolotnoColors colors,
    required String title,
    required String coord,
    required String time,
    required String levelText,
    required Color levelColor,
    required Color levelBg,
    required int confirms,
    Map<String, dynamic>? rawDefect,
  }) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PotholeDetailsScreen(defect: rawDefect),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.edge2)),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: colors.surf2,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.broken_image_outlined,
                color: colors.ink3,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: AppTheme.fontUi,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    coord,
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 10.5,
                      color: colors.ink3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: levelBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          levelText,
                          style: TextStyle(
                            fontFamily: AppTheme.fontUi,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: levelColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.check_rounded, size: 13, color: colors.ink2),
                      const SizedBox(width: 2),
                      Text(
                        "$confirms",
                        style: TextStyle(
                          fontFamily: AppTheme.fontUi,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.ink2,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        time,
                        style: TextStyle(
                          fontFamily: AppTheme.fontMono,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.ink3,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
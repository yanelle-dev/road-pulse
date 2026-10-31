import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;

import 'address_service.dart';
import 'api_service.dart';
import 'app_theme.dart';
import 'calculations.dart';
import 'gps.dart';
import 'pothole_details_screen.dart';
import 'widgets/nav_arrow.dart';
import 'widgets/road_ribbon.dart';

class MapScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateToTab;

  const MapScreen({super.key, this.onNavigateToTab});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  /// Ниже этой скорости курс GPS шумит и стрелка «дрожит»: остаётся последний уверенный курс.
  static const double _minHeadingSpeedMs = 1.5;

  final MapController _mapController = MapController();
  List<dynamic> _bumps = [];
  LatLng? _myLocation;
  double? _headingDeg;
  double _currentSpeedKmh = 0.0;
  bool _isServiceRunning = false;
  StreamSubscription<Position>? _positionStream;
  late Future<UserStats> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = ApiService.getUserStats();
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

  /// Позиция, скорость и курс из одного места: раньше это были две копии в слушателе и в _locateUser.
  void _applyPosition(Position pos) {
    _myLocation = LatLng(pos.latitude, pos.longitude);
    _currentSpeedKmh = (pos.speed * 3.6).clamp(0.0, 999.0);

    if (pos.speed < _minHeadingSpeedMs || pos.heading < 0) return;
    final prev = _headingDeg;
    if (prev == null) {
      _headingDeg = pos.heading;
      return;
    }
    var delta = (pos.heading - prev) % 360;
    if (delta > 180) delta -= 360;
    _headingDeg = prev + delta; // без обнуления на 360°, иначе стрелка крутится «через весь круг»
  }

  void _initSpeedListener() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: gpsStreamSettings(distanceFilter: 2),
    ).listen((pos) {
      if (mounted) {
        setState(() => _applyPosition(pos));
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
        setState(() => _applyPosition(pos));
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

  Color _severityColor(PolotnoColors colors, int severity) =>
      severity == 3 ? colors.s3 : (severity == 2 ? colors.s2 : colors.s1);

  /// Линии участка тряски: сервер присылает их по отдельности (`lines`), старые ответы — одной ломаной.
  List<List<LatLng>> _linesOf(dynamic bump) {
    if (bump['defect_type'] != 'rough_road') return const [];

    final rawLines = bump['lines'];
    final List<dynamic> sources = (rawLines is List && rawLines.isNotEmpty)
        ? rawLines
        : [bump['coordinates']];

    final result = <List<LatLng>>[];
    for (final source in sources) {
      if (source is! List) continue;
      final points = <LatLng>[
        for (final pt in source)
          if (pt is List && pt.length >= 2)
            LatLng((pt[0] as num).toDouble(), (pt[1] as num).toDouble()),
      ];
      if (points.length >= 2) result.add(points);
    }
    return result;
  }

  List<Polyline> _buildPolylines(PolotnoColors colors) {
    final List<Polyline> polylines = [];

    for (final b in _bumps) {
      final lines = _linesOf(b);
      if (lines.isEmpty) continue;

      final bool isConfirmed = b['is_confirmed'] ?? false;
      final lineColor = _severityColor(colors, defectSeverity(b));

      for (final points in lines) {
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
    }

    return polylines;
  }

  List<CircleMarker> _buildCircles(PolotnoColors colors) {
    final List<CircleMarker> circles = [];

    for (final b in _bumps) {
      final bool isConfirmed = b['is_confirmed'] ?? false;
      if (!isConfirmed) continue;

      // Участки с геометрией линий уже отрисованы в PolylineLayer
      if (_linesOf(b).isNotEmpty) continue;

      final double lat = (b['lat'] ?? b['latitude'] ?? 0.0).toDouble();
      final double lon = (b['lon'] ?? b['longitude'] ?? 0.0).toDouble();
      final LatLng point = LatLng(lat, lon);

      final severity = defectSeverity(b);
      final bumpColor = _severityColor(colors, severity);
      final double radius = severity == 3 ? 16.0 : (severity == 2 ? 12.0 : 10.0);

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

      if (_linesOf(b).isNotEmpty) continue;

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
                      width: NavArrow.size,
                      height: NavArrow.size,
                      child: NavArrow(headingDeg: _headingDeg),
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
                setState(() => _statsFuture = ApiService.getUserStats());
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
    final severities = [for (final b in _bumps) defectSeverity(b)];
    final int hardCount = severities.where((s) => s == 3).length;
    final int mediumCount = severities.where((s) => s == 2).length;
    final int smoothCount = severities.length - hardCount - mediumCount;

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
                segments: severities.isEmpty
                    ? [RibbonSegment(flex: 1, color: colors.s1)]
                    : [
                        RibbonSegment(flex: smoothCount / severities.length, color: colors.s1),
                        RibbonSegment(flex: mediumCount / severities.length, color: colors.s2),
                        RibbonSegment(flex: hardCount / severities.length, color: colors.s3),
                      ],
              ),
              const SizedBox(height: 16),
              FutureBuilder<UserStats>(
                future: _statsFuture,
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
                  final distM = (bump['calc_distance_m'] as double?) ?? 0.0;
                  final distStr = distM >= 1000 ? "${(distM / 1000).toStringAsFixed(1)} км" : "${distM.round()} м";
                  final confirms = bump['total_hits'] ?? bump['unique_users'] ?? 1;
                  final severity = defectSeverity(bump);

                  return _buildDefectRow(
                    colors: colors,
                    title: bump['defect_type'] == 'rough_road' ? "Неровная дорога" : "Дефект полотна",
                    coord: AddressService.fromDefect(bump) ??
                        "${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}",
                    time: distStr,
                    levelText: severity == 3 ? "ЖЁСТКО" : (severity == 2 ? "ЗАМЕТНО" : "РОВНО"),
                    levelColor: _severityColor(colors, severity),
                    levelBg: severity == 3 ? colors.s3Soft : (severity == 2 ? colors.s2Soft : colors.s1Soft),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
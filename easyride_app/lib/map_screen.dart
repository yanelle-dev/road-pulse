import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';
import 'app_theme.dart';
import 'widgets/road_ribbon.dart';
import 'pothole_details_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadBumps();
    _locateUser();
  }

  Future<void> _locateUser() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() {
          _myLocation = LatLng(pos.latitude, pos.longitude);
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

  List<CircleMarker> _buildCircles(PolotnoColors colors) {
    final List<CircleMarker> circles = [];

    for (final b in _bumps) {
      final bool isConfirmed = b['is_confirmed'] ?? false;
      if (!isConfirmed) continue;

      final double force = (b['max_force'] ?? 0.0).toDouble();
      final LatLng point = LatLng(b['lat'], b['lon']);

      Color bumpColor = colors.s1;
      double radius = 10.0;

      if (force > 30) {
        bumpColor = colors.s3;
        radius = 16.0;
      } else if (force > 20) {
        bumpColor = colors.s2;
        radius = 12.0;
      }

      // Внешний полупрозрачный ореол
      circles.add(
        CircleMarker(
          point: point,
          color: bumpColor.withValues(alpha: 0.22),
          borderStrokeWidth: 0,
          useRadiusInMeter: true,
          radius: radius * 1.8,
        ),
      );

      // Ядро дефекта
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

      final LatLng point = LatLng(b['lat'], b['lon']);
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

    final tileUrl = isDark
        ? 'https://{s}.basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}{r}.png'
        : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';

    return Scaffold(
      backgroundColor: colors.voidBg,
      body: Stack(
        children: [
          // 1. Карта
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(55.751244, 37.618423),
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: tileUrl,
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.easyride.app',
              ),
              CircleLayer(circles: _buildCircles(colors)),
              MarkerLayer(markers: [
                ..._buildMarkers(colors),
                if (_myLocation != null)
                  Marker(
                    point: _myLocation!,
                    width: 36,
                    height: 36,
                    child: _buildUserLocationMarker(colors),
                  ),
              ]),
            ],
          ),

          // 2. Верхняя статус-капсула записи
          Positioned(
            top: 54,
            left: 16,
            child: _buildRecordCapsule(colors),
          ),

          // 3. Строка поиска «Куда едем?»
          Positioned(
            top: 106,
            left: 16,
            right: 16,
            child: _buildSearchBar(colors),
          ),

          // 4. Плавающие кнопки управления справа
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

          // 5. Выдвижная шторка
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
                    color: colors.s3,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "ЗАПИСЬ",
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
                  "58 км/ч",
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
                    "Впереди 4,2 км",
                    style: TextStyle(
                      fontFamily: AppTheme.fontDisplay,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                      letterSpacing: -0.8,
                    ),
                  ),
                  Text(
                    "ДО СОКОЛА",
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
                currentPosition: 0.19,
                segments: [
                  RibbonSegment(flex: 0.22, color: colors.s1),
                  RibbonSegment(flex: 0.13, color: colors.s2),
                  RibbonSegment(flex: 0.09, color: colors.s3),
                  RibbonSegment(flex: 0.26, color: colors.s1),
                  RibbonSegment(flex: 0.11, color: colors.s3),
                  RibbonSegment(flex: 0.19, color: colors.s2),
                ],
              ),
              const SizedBox(height: 7),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "ВЫ ЗДЕСЬ",
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 9.5,
                      color: colors.ink3,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    "ЧЕРЕЗ 4,2 КМ",
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 9.5,
                      color: colors.ink3,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _buildStatPill(colors, "7", "ЖЁСТКИХ", colors.s3),
                  const SizedBox(width: 8),
                  _buildStatPill(colors, "3,2", "КМ ЗАПИСАНО", colors.ink),
                  const SizedBox(width: 8),
                  _buildStatPill(colors, "+120", "ОЧКОВ", colors.markInk),
                ],
              ),
              const SizedBox(height: 26),
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
                      "Все 24",
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
              _buildDefectRow(
                colors: colors,
                title: "Ленинградский пр-т, 78",
                coord: "55.75121, 37.61843",
                time: "09:12 · 1,2 км",
                levelText: "ЖЁСТКО",
                levelColor: colors.s3,
                levelBg: colors.s3Soft,
                confirms: 12,
              ),
              _buildDefectRow(
                colors: colors,
                title: "Ул. Красина, 14",
                coord: "55.76904, 37.58311",
                time: "08:47 · 2,6 км",
                levelText: "ЗАМЕТНО",
                levelColor: colors.s2,
                levelBg: colors.s2Soft,
                confirms: 7,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  side: BorderSide(color: colors.edge),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

  Widget _buildStatPill(PolotnoColors colors, String val, String label, Color valColor) {
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
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: valColor,
                letterSpacing: -0.8,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 9,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.1,
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
  }) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PotholeDetailsScreen()),
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
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: colors.surf2,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.broken_image_outlined, color: colors.ink3, size: 24),
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
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
                          fontFamily: AppTheme.fontUi,
                          fontSize: 11,
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
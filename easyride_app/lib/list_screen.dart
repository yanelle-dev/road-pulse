import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'app_theme.dart';
import 'pothole_details_screen.dart';
import 'api_service.dart';
import 'widgets/road_ribbon.dart';

class ListScreen extends StatefulWidget {
  const ListScreen({super.key});

  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  int _activeFilterIndex = 0;
  bool _isLoading = true;
  List<dynamic> _allBumps = [];
  List<dynamic> _filteredBumps = [];

  final List<String> _filters = ["Сегодня", "Неделя", "Месяц", "Всё время"];

  @override
  void initState() {
    super.initState();
    _loadBumps();
  }

  Future<void> _loadBumps() async {
    setState(() => _isLoading = true);
    try {
      final bumps = await ApiService.getBumps();
      if (mounted) {
        setState(() {
          _allBumps = bumps;
          _applyFilter();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Ошибка при загрузке списка ям: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    final now = DateTime.now();

    setState(() {
      _filteredBumps = _allBumps.where((bump) {
        final bumpDate = _parseDate(bump);
        final difference = now.difference(bumpDate);

        switch (_activeFilterIndex) {
          case 0: // Сегодня
            return bumpDate.year == now.year &&
                bumpDate.month == now.month &&
                bumpDate.day == now.day;
          case 1: // Неделя
            return difference.inDays <= 7;
          case 2: // Месяц
            return difference.inDays <= 30;
          case 3: // Всё время
          default:
            return true;
        }
      }).toList();

      _filteredBumps.sort((a, b) {
        final dateA = _parseDate(a);
        final dateB = _parseDate(b);
        return dateB.compareTo(dateA);
      });
    });
  }

  DateTime _parseDate(dynamic bump) {
    final dateStr = bump['created_at'] ?? bump['timestamp'];
    if (dateStr != null) {
      return DateTime.tryParse(dateStr.toString()) ?? DateTime.now();
    }
    return DateTime.now();
  }

  Future<String> _getAddress(double lat, double lon) async {
    try {
      final geocoding = Geocoding();
      List<Placemark> placemarks = await geocoding.placemarkFromCoordinates(lat, lon);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        return "${p.street ?? 'Улица'}, ${p.locality ?? 'Москва'}";
      }
    } catch (_) {}
    return "Ш: ${lat.toStringAsFixed(4)}, Д: ${lon.toStringAsFixed(4)}";
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.voidBg,
      body: SafeArea(
        bottom: false,
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: colors.markInk))
            : RefreshIndicator(
                color: colors.markInk,
                onRefresh: _loadBumps,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.only(bottom: 120),
                  children: [
                    _buildHeader(colors),
                    _buildSummaryCard(colors),
                    _buildFilterChips(colors),
                    if (_filteredBumps.isEmpty)
                      _buildEmptyState(colors)
                    else
                      ..._filteredBumps.map((bump) => _buildDefectCard(colors, bump)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeader(PolotnoColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Дефекты",
            style: TextStyle(
              fontFamily: AppTheme.fontDisplay,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: colors.ink,
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Всё, что записал ваш телефон",
            style: TextStyle(
              fontFamily: AppTheme.fontUi,
              fontSize: 14,
              color: colors.ink2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(PolotnoColors colors) {
    int countS1 = 0;
    int countS2 = 0;
    int countS3 = 0;

    for (final b in _allBumps) {
      final double force = (b['max_force'] ?? 0.0).toDouble();
      if (force > 30) {
        countS3++;
      } else if (force > 20) {
        countS2++;
      } else {
        countS1++;
      }
    }

    final int total = _allBumps.length;
    final double flexS1 = total == 0 ? 0.33 : (countS1 / total);
    final double flexS2 = total == 0 ? 0.33 : (countS2 / total);
    final double flexS3 = total == 0 ? 0.34 : (countS3 / total);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surf,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.edge2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "$total",
                style: TextStyle(
                  fontFamily: AppTheme.fontDisplay,
                  fontSize: 46,
                  fontWeight: FontWeight.w800,
                  color: colors.ink,
                  height: 0.9,
                  letterSpacing: -2.0,
                ),
              ),
              const SizedBox(width: 14),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "найдено за всё время",
                      style: TextStyle(
                        fontFamily: AppTheme.fontUi,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: colors.ink,
                      ),
                    ),
                    Text(
                      "${_allBumps.where((b) => b['is_confirmed'] == true).length} подтверждены другими",
                      style: TextStyle(
                        fontFamily: AppTheme.fontUi,
                        fontSize: 12.5,
                        color: colors.ink2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          RoadRibbon(
            height: 8,
            segments: [
              RibbonSegment(flex: flexS1, color: colors.s1),
              RibbonSegment(flex: flexS2, color: colors.s2),
              RibbonSegment(flex: flexS3, color: colors.s3),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildRibbonLegend(colors.s1, "$countS1 ровно", colors),
              const SizedBox(width: 14),
              _buildRibbonLegend(colors.s2, "$countS2 заметно", colors),
              const SizedBox(width: 14),
              _buildRibbonLegend(colors.s3, "$countS3 жёстко", colors),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRibbonLegend(Color color, String text, PolotnoColors colors) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            fontFamily: AppTheme.fontMono,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: colors.ink3,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChips(PolotnoColors colors) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: List.generate(_filters.length, (index) {
          final bool isActive = _activeFilterIndex == index;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() => _activeFilterIndex = index);
                _applyFilter();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive ? colors.mark : colors.surf,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isActive ? colors.mark : colors.edge2,
                  ),
                ),
                child: Text(
                  _filters[index],
                  style: TextStyle(
                    fontFamily: AppTheme.fontUi,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isActive ? colors.onMark : colors.ink2,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDefectCard(PolotnoColors colors, dynamic bump) {
    final double lat = (bump['latitude'] ?? bump['lat'] ?? 0.0).toDouble();
    final double lon = (bump['longitude'] ?? bump['lon'] ?? 0.0).toDouble();
    final double force = (bump['max_force'] ?? 0.0).toDouble();
    final int confirms = bump['total_hits'] ?? bump['unique_users'] ?? 1;

    Color levelColor = colors.s1;
    Color levelBg = colors.s1Soft;
    String levelText = "РОВНО";
    String sizeStr = "S";

    if (force > 30) {
      levelColor = colors.s3;
      levelBg = colors.s3Soft;
      levelText = "ЖЁСТКО";
      sizeStr = "L";
    } else if (force > 20) {
      levelColor = colors.s2;
      levelBg = colors.s2Soft;
      levelText = "ЗАМЕТНО";
      sizeStr = "M";
    }

    final date = _parseDate(bump);
    final timeStr = "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surf,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.edge2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PotholeDetailsScreen()),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Текстурный плейсхолдер с бейджем размера S/M/L
                Stack(
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: colors.asphalt,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colors.edge2),
                      ),
                      child: Icon(Icons.broken_image_outlined, color: colors.ink3, size: 28),
                    ),
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          sizeStr,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontMono,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FutureBuilder<String>(
                        future: _getAddress(lat, lon),
                        builder: (context, snapshot) {
                          return Text(
                            snapshot.data ?? "Определение адреса...",
                            style: TextStyle(
                              fontFamily: AppTheme.fontUi,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: colors.ink,
                              letterSpacing: -0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          );
                        },
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}",
                        style: TextStyle(
                          fontFamily: AppTheme.fontMono,
                          fontSize: 11,
                          color: colors.ink3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "$timeStr · 1,2 км",
                        style: TextStyle(
                          fontFamily: AppTheme.fontUi,
                          fontSize: 12,
                          color: colors.ink2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: levelBg,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              levelText,
                              style: TextStyle(
                                fontFamily: AppTheme.fontUi,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: levelColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.check_rounded, size: 14, color: colors.ink2),
                          const SizedBox(width: 2),
                          Text(
                            "$confirms",
                            style: TextStyle(
                              fontFamily: AppTheme.fontUi,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: colors.ink2,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              border: Border.all(color: colors.markLine),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.navigation_outlined, size: 11, color: colors.markInk),
                                const SizedBox(width: 4),
                                Text(
                                  "Объезд",
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontUi,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: colors.markInk,
                                  ),
                                ),
                              ],
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
        ),
      ),
    );
  }

  Widget _buildEmptyState(PolotnoColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 48, color: colors.ink3),
            const SizedBox(height: 12),
            Text(
              "В этом периоде дефектов не найдено",
              style: TextStyle(
                fontFamily: AppTheme.fontUi,
                fontSize: 14,
                color: colors.ink2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
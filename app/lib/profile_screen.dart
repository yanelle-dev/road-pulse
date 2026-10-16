import 'package:flutter/material.dart';

import 'achievement_service.dart';
import 'api_service.dart';
import 'app_theme.dart';
import 'calculations.dart';
import 'fresh_prefs.dart';
import 'screens/account_screen.dart';
import 'widgets/road_ribbon.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<UserStats> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = freshPrefs().then((_) => ApiService.getUserStats());
    AchievementService.getTotalDistanceMeters().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _refreshProfileData() async {
    await freshPrefs();
    await AchievementService.getTotalDistanceMeters();
    if (mounted) {
      setState(() {
        _statsFuture = ApiService.getUserStats();
      });
    }
    await _statsFuture;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.voidBg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: colors.mark,
          onRefresh: _refreshProfileData,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              _buildHeader(context, colors),
              _buildCommunityBadge(colors, _statsFuture),
              _buildStatsGrid(colors, _statsFuture),
              _buildLastTrip(colors),
              _buildAchievements(colors),
              _buildActivityHeatmap(colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, PolotnoColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: FutureBuilder<Map<String, dynamic>>(
        future: ApiService.getUserProfile(),
        builder: (context, snapshot) {
          final name = snapshot.data?['name'] ?? 'Водитель';
          final city = snapshot.data?['city'] ?? 'Москва';
          final clearanceVal = snapshot.data?['car_clearance'];
          final clearanceStr = (clearanceVal is int && clearanceVal > 0)
              ? "клиренс $clearanceVal мм"
              : "клиренс не указан";

          final parts = name.trim().split(RegExp(r'\s+'));
          String initials = "В";
          if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
            initials = "${parts[0][0]}${parts[1][0]}".toUpperCase();
          } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
            initials = parts[0]
                .substring(0, parts[0].length >= 2 ? 2 : 1)
                .toUpperCase();
          }

          return Row(
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: colors.mark,
                  borderRadius: BorderRadius.circular(24),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: TextStyle(
                    fontFamily: AppTheme.fontDisplay,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: colors.onMark,
                    letterSpacing: -0.8,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontFamily: AppTheme.fontDisplay,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: colors.ink,
                        letterSpacing: -0.6,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      "$city · $clearanceStr",
                      style: TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 11.5,
                        color: colors.ink3,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: colors.surf,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                    side: BorderSide(color: colors.edge2),
                  ),
                ),
                icon: Icon(
                  Icons.settings_outlined,
                  color: colors.ink,
                  size: 20,
                ),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AccountScreen()),
                  );
                  if (mounted) {
                    setState(() {
                      _statsFuture = ApiService.getUserStats();
                    });
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCommunityBadge(PolotnoColors colors, Future<UserStats> statsFuture) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FutureBuilder<UserStats>(
          future: statsFuture,
          builder: (context, snapshot) {
            final stats = snapshot.data;
            final rating = stats?.rating ?? 0;
            final percentile = stats?.communityPercentile;
            final badgeText = communityBadgeText(rating, percentile: percentile);

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: colors.markSoft,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: colors.markLine),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded, size: 14, color: colors.markInk),
                  const SizedBox(width: 6),
                  Text(
                    badgeText,
                    style: TextStyle(
                      fontFamily: AppTheme.fontUi,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.markInk,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatsGrid(PolotnoColors colors, Future<UserStats> statsFuture) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: FutureBuilder<UserStats>(
        future: statsFuture,
        builder: (context, snapshot) {
          final stats = snapshot.data ?? UserStats.empty();

          final defectsVal = _formatNumber(stats.totalDefects);
          final kmVal = _formatKm(stats.totalKm);
          final ratingVal = _formatNumber(stats.rating);
          final savedVal = _formatNumber(stats.savedSuspensions);

          return Column(
            children: [
              Row(
                children: [
                  _buildStatCard(
                    colors,
                    defectsVal,
                    "Дефектов найдено",
                    "зачтено сервером",
                    colors.s1,
                  ),
                  const SizedBox(width: 8),
                  _buildStatCard(
                    colors,
                    kmVal,
                    "Километров записано",
                    "${(stats.totalKm * 1000).round()} м трекинга",
                    colors.s1,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildStatCard(
                    colors,
                    ratingVal,
                    "Очков рейтинга",
                    "${stats.unlockedAchievements} наград · ${stats.streakDays} дн",
                    colors.s1,
                  ),
                  const SizedBox(width: 8),
                  _buildStatCard(
                    colors,
                    savedVal,
                    "Подвесок спасено",
                    "по объездам",
                    colors.s1,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  static String _formatNumber(int number) {
    final str = number.toString();
    final regExp = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return str.replaceAllMapped(regExp, (Match m) => '${m[1]} ');
  }

  static String _formatKm(double km) {
    if (km >= 100.0) {
      return _formatNumber(km.round());
    }
    return km.toStringAsFixed(2).replaceAll('.', ',');
  }

  Widget _buildStatCard(
    PolotnoColors colors,
    String val,
    String title,
    String diff,
    Color diffColor,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
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
                fontSize: 27,
                fontWeight: FontWeight.w700,
                color: colors.ink,
                letterSpacing: -1.0,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              title,
              style: TextStyle(
                fontFamily: AppTheme.fontUi,
                fontSize: 12.5,
                color: colors.ink2,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              diff,
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 10.0,
                fontWeight: FontWeight.w500,
                color: diffColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastTrip(PolotnoColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
      child: FutureBuilder<TripData?>(
        future: ApiService.getLastTrip(),
        builder: (context, snapshot) {
          final trip = snapshot.data;

          if (trip == null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Последняя поездка",
                  style: TextStyle(
                    fontFamily: AppTheme.fontUi,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.ink,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 11),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colors.surf,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: colors.edge2),
                  ),
                  child: Center(
                    child: Text(
                      "Нет завершённых поездок. Запустите запись в разделе «Запись».",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTheme.fontUi,
                        fontSize: 13,
                        color: colors.ink3,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          final now = DateTime.now();
          final isToday = trip.startedAt.year == now.year &&
              trip.startedAt.month == now.month &&
              trip.startedAt.day == now.day;
          final dateStr = isToday
              ? "СЕГОДНЯ"
              : "${trip.startedAt.day.toString().padLeft(2, '0')}.${trip.startedAt.month.toString().padLeft(2, '0')}";

          final km = (trip.distanceMeters / 1000.0).toStringAsFixed(1);
          final durationMin = trip.endedAt != null
              ? trip.endedAt!.difference(trip.startedAt).inMinutes
              : 0;
          final durationStr = durationMin > 0 ? "$durationMin мин" : "< 1 мин";

          return Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Последняя поездка",
                    style: TextStyle(
                      fontFamily: AppTheme.fontUi,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.2,
                      color: colors.ink3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Container(
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
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          "$km КМ",
                          style: TextStyle(
                            fontFamily: AppTheme.fontDisplay,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: colors.ink,
                            letterSpacing: -0.8,
                            height: 0.9,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "· $durationStr · ${trip.defectsCount} дефектов",
                          style: TextStyle(
                            fontFamily: AppTheme.fontMono,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: colors.ink2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    RoadRibbon(
                      height: 12,
                      segments: [
                        RibbonSegment(flex: trip.smoothRatio, color: colors.s1),
                        RibbonSegment(flex: trip.mediumRatio, color: colors.s2),
                        RibbonSegment(flex: trip.hardRatio, color: colors.s3),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "СТАРТ",
                          style: TextStyle(
                            fontFamily: AppTheme.fontMono,
                            fontSize: 9.5,
                            color: colors.ink3,
                            letterSpacing: 1.0,
                          ),
                        ),
                        Text(
                          "ФИНИШ",
                          style: TextStyle(
                            fontFamily: AppTheme.fontMono,
                            fontSize: 9.5,
                            color: colors.ink3,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAchievements(PolotnoColors colors) {
    return FutureBuilder<List<Achievement>>(
      future: AchievementService.getAchievements(),
      builder: (context, snapshot) {
        final all = snapshot.data ?? [];
        final unlockedCount = all.where((a) => a.isUnlocked).length;

        final displayList = List<Achievement>.from(all)
          ..sort((a, b) {
            if (a.isUnlocked != b.isUnlocked) {
              return a.isUnlocked ? -1 : 1;
            }
            return b.progressRatio.compareTo(a.progressRatio);
          });
        final topCards = displayList.take(8).toList();

        return Padding(
          padding: const EdgeInsets.only(top: 26),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Достижения",
                      style: TextStyle(
                        fontFamily: AppTheme.fontUi,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _showAchievementsSheet(context, colors),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colors.markSoft,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          "$unlockedCount из 30 · ВСЕ",
                          style: TextStyle(
                            fontFamily: AppTheme.fontMono,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: colors.markInk,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 11),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: topCards.map((ach) {
                    final isDone = ach.isUnlocked;
                    return GestureDetector(
                      onTap: () => _showAchievementsSheet(context, colors),
                      child: Container(
                        width: 112,
                        margin: const EdgeInsets.only(right: 9),
                        padding: const EdgeInsets.symmetric(
                          vertical: 13,
                          horizontal: 10,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surf,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isDone ? colors.mark : colors.edge2,
                            width: isDone ? 1.5 : 1.0,
                          ),
                        ),
                        child: Column(
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isDone
                                        ? colors.markSoft
                                        : colors.surf2,
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: Icon(
                                    ach.icon,
                                    color: isDone
                                        ? colors.markInk
                                        : colors.ink3,
                                    size: 21,
                                  ),
                                ),
                                if (isDone)
                                  Positioned(
                                    right: -4,
                                    bottom: -4,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: colors.s1,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.check,
                                        size: 10,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 9),
                            Text(
                              ach.title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppTheme.fontUi,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: colors.ink,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 7),
                            if (isDone)
                              Text(
                                "ПОЛУЧЕНО",
                                style: TextStyle(
                                  fontFamily: AppTheme.fontMono,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w700,
                                  color: colors.s1,
                                ),
                              )
                            else ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: ach.progressRatio,
                                  minHeight: 4,
                                  backgroundColor: colors.surf2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    colors.mark,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "${ach.current}/${ach.target}",
                                style: TextStyle(
                                  fontFamily: AppTheme.fontMono,
                                  fontSize: 8.5,
                                  color: colors.ink3,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAchievementsSheet(BuildContext context, PolotnoColors colors) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AllAchievementsSheet(colors: colors),
    );
  }

  Widget _buildActivityHeatmap(PolotnoColors colors) {
    const days = ["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "ВС"];

    final levels = [
      colors.surf2,
      colors.markSoft,
      colors.mark.withValues(alpha: 0.62),
      colors.mark,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
      child: FutureBuilder<UserActivityData>(
        future: ApiService.getActivityData(),
        builder: (context, snapshot) {
          final data = snapshot.data ?? UserActivityData.empty();
          final streakText = _formatStreak(data.streakDays);

          return Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Активность",
                    style: TextStyle(
                      fontFamily: AppTheme.fontUi,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    streakText,
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.1,
                      color: data.streakDays > 0 ? colors.markInk : colors.ink3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surf,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: colors.edge2),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: days.map((d) {
                        return SizedBox(
                          width: 28,
                          child: Text(
                            d,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: AppTheme.fontMono,
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                              color: colors.ink3,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            crossAxisSpacing: 5,
                            mainAxisSpacing: 5,
                          ),
                      itemCount: 28,
                      itemBuilder: (context, index) {
                        final dayItem = index < data.days.length
                            ? data.days[index]
                            : null;
                        final level = dayItem?.level ?? 0;
                        final count = dayItem?.count ?? 0;
                        final isToday = dayItem?.isToday ?? false;

                        String tooltipText;
                        if (dayItem == null || dayItem.isFuture) {
                          tooltipText = "Будущий день";
                        } else {
                          final dateStr =
                              "${dayItem.date.day.toString().padLeft(2, '0')}.${dayItem.date.month.toString().padLeft(2, '0')}";
                          if (count == 0) {
                            tooltipText = "$dateStr: не заходил";
                          } else {
                            tooltipText = "$dateStr: ${_formatVisits(count)}";
                          }
                          if (isToday) {
                            tooltipText = "Сегодня ($tooltipText)";
                          }
                        }

                        return Tooltip(
                          message: tooltipText,
                          child: Container(
                            decoration: BoxDecoration(
                              color: levels[level.clamp(0, 3)],
                              borderRadius: BorderRadius.circular(6),
                              border: isToday
                                  ? Border.all(color: colors.mark, width: 1.5)
                                  : null,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 13),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          data.totalVisits == 0
                              ? "НЕТ ВХОДОВ"
                              : "ВХОДОВ: ${data.totalVisits} (${data.activeDays}/28 ДН)",
                          style: TextStyle(
                            fontFamily: AppTheme.fontMono,
                            fontSize: 8.5,
                            color: colors.ink3,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "РЕЖЕ",
                              style: TextStyle(
                                fontFamily: AppTheme.fontMono,
                                fontSize: 8.5,
                                color: colors.ink3,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(width: 6),
                            ...levels.map(
                              (c) => Container(
                                width: 12,
                                height: 12,
                                margin: const EdgeInsets.only(right: 3),
                                decoration: BoxDecoration(
                                  color: c,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              "ЧАЩЕ",
                              style: TextStyle(
                                fontFamily: AppTheme.fontMono,
                                fontSize: 8.5,
                                color: colors.ink3,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _formatStreak(int streak) {
    if (streak == 0) return "0 ДНЕЙ";
    final mod10 = streak % 10;
    final mod100 = streak % 100;
    if (mod100 >= 11 && mod100 <= 14) {
      return "$streak ДНЕЙ ПОДРЯД";
    }
    if (mod10 == 1) {
      return "$streak ДЕНЬ ПОДРЯД";
    }
    if (mod10 >= 2 && mod10 <= 4) {
      return "$streak ДНЯ ПОДРЯД";
    }
    return "$streak ДНЕЙ ПОДРЯД";
  }

  static String _formatVisits(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod100 >= 11 && mod100 <= 14) {
      return "$count входов";
    }
    if (mod10 == 1) {
      return "$count вход";
    }
    if (mod10 >= 2 && mod10 <= 4) {
      return "$count входа";
    }
    return "$count входов";
  }
}

class _AllAchievementsSheet extends StatefulWidget {
  final PolotnoColors colors;

  const _AllAchievementsSheet({required this.colors});

  @override
  State<_AllAchievementsSheet> createState() => _AllAchievementsSheetState();
}

class _AllAchievementsSheetState extends State<_AllAchievementsSheet> {
  int _activeCategoryIndex = 0;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: colors.voidBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: colors.edge, width: 1)),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 5,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: colors.edge,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Все 30 достижений",
                      style: TextStyle(
                        fontFamily: AppTheme.fontDisplay,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: colors.ink,
                        letterSpacing: -0.6,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: colors.ink3),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                child: Row(
                  children: List.generate(
                    AchievementService.categories.length,
                    (idx) {
                      final cat = AchievementService.categories[idx];
                      final isSel = _activeCategoryIndex == idx;
                      return GestureDetector(
                        onTap: () => setState(() => _activeCategoryIndex = idx),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: isSel ? colors.mark : colors.surf,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: isSel ? colors.mark : colors.edge2,
                            ),
                          ),
                          child: Text(
                            cat,
                            style: TextStyle(
                              fontFamily: AppTheme.fontUi,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: isSel ? colors.onMark : colors.ink2,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<Achievement>>(
                  future: AchievementService.getAchievements(),
                  builder: (context, snapshot) {
                    final list = snapshot.data ?? [];
                    final filtered = list.where((a) {
                      if (_activeCategoryIndex == 0) return true;
                      final selectedCategory =
                          AchievementService.categories[_activeCategoryIndex];
                      return a.category == selectedCategory;
                    }).toList();

                    return ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final ach = filtered[index];
                        final isDone = ach.isUnlocked;

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colors.surf,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isDone ? colors.mark : colors.edge2,
                              width: isDone ? 1.4 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: isDone
                                      ? colors.markSoft
                                      : colors.surf2,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  ach.icon,
                                  color: isDone ? colors.markInk : colors.ink3,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            ach.title,
                                            style: TextStyle(
                                              fontFamily: AppTheme.fontUi,
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w700,
                                              color: colors.ink,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isDone
                                                ? colors.s1Soft
                                                : colors.surf2,
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Text(
                                            isDone
                                                ? "ВЫПОЛНЕНО"
                                                : "${ach.current}/${ach.target}",
                                            style: TextStyle(
                                              fontFamily: AppTheme.fontMono,
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w700,
                                              color: isDone
                                                  ? colors.s1
                                                  : colors.ink3,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      ach.description,
                                      style: TextStyle(
                                        fontFamily: AppTheme.fontUi,
                                        fontSize: 12,
                                        color: colors.ink2,
                                        height: 1.25,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: LinearProgressIndicator(
                                        value: ach.progressRatio,
                                        minHeight: 4,
                                        backgroundColor: colors.surf2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              isDone ? colors.s1 : colors.mark,
                                            ),
                                      ),
                                    ),
                                  ],
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
      },
    );
  }
}
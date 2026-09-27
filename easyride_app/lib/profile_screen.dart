import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'widgets/road_ribbon.dart';
import 'screens/account_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.voidBg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            _buildHeader(context, colors),
            _buildCommunityBadge(colors),
            _buildStatsGrid(colors),
            _buildLastTrip(colors),
            _buildAchievements(colors),
            _buildActivityHeatmap(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, PolotnoColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          // Желтый квадратный аватар с инициалами
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: colors.mark,
              borderRadius: BorderRadius.circular(24),
            ),
            alignment: Alignment.center,
            child: Text(
              "АК",
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
                  "Алексей\nКозлов",
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
                  "Москва · с марта 2026",
                  style: TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 11.5,
                    color: colors.ink3,
                  ),
                ),
              ],
            ),
          ),
          // Кнопка перехода в настройки аккаунта
          IconButton(
            style: IconButton.styleFrom(
              backgroundColor: colors.surf,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
                side: BorderSide(color: colors.edge2),
              ),
            ),
            icon: Icon(Icons.settings_outlined, color: colors.ink, size: 20),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AccountScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCommunityBadge(PolotnoColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
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
                "Топ 5% сообщества",
                style: TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.markInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsGrid(PolotnoColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        children: [
          Row(
            children: [
              _buildStatCard(colors, "147", "Дефектов найдено", "+12 за неделю", colors.s1),
              const SizedBox(width: 8),
              _buildStatCard(colors, "1 234", "Километров записано", "+86 км", colors.s1),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildStatCard(colors, "2 840", "Очков рейтинга", "+340", colors.s1),
              const SizedBox(width: 8),
              _buildStatCard(colors, "12", "Подвесок спасено", "по объездам", colors.s1),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(PolotnoColors colors, String val, String title, String diff, Color diffColor) {
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
                fontSize: 29,
                fontWeight: FontWeight.w700,
                color: colors.ink,
                letterSpacing: -1.2,
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
                fontSize: 10.5,
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
      child: Column(
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
                "ВЧЕРА · 18:40",
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
                      "28,4",
                      style: TextStyle(
                        fontFamily: AppTheme.fontDisplay,
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        color: colors.ink,
                        letterSpacing: -1.2,
                        height: 0.9,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "КМ · 41 МИН",
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
                const SizedBox(height: 15),
                RoadRibbon(
                  height: 12,
                  segments: [
                    RibbonSegment(flex: 0.31, color: colors.s1),
                    RibbonSegment(flex: 0.08, color: colors.s3),
                    RibbonSegment(flex: 0.17, color: colors.s2),
                    RibbonSegment(flex: 0.22, color: colors.s1),
                    RibbonSegment(flex: 0.06, color: colors.s3),
                    RibbonSegment(flex: 0.16, color: colors.s2),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "ДМИТРОВСКОЕ Ш.",
                      style: TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 9.5,
                        color: colors.ink3,
                        letterSpacing: 1.0,
                      ),
                    ),
                    Text(
                      "САДОВОЕ",
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
      ),
    );
  }

  Widget _buildAchievements(PolotnoColors colors) {
    final achievements = [
      {"icon": Icons.adjust_rounded, "title": "Охотник\nза ямами", "color": colors.s3},
      {"icon": Icons.shield_outlined, "title": "Спаситель\nподвесок", "color": colors.markInk},
      {"icon": Icons.bolt_rounded, "title": "1 000 км\nза месяц", "color": colors.s1},
      {"icon": Icons.nightlight_round, "title": "Ночной\nдозор", "color": colors.ink2},
    ];

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
                Text(
                  "4 из 18",
                  style: TextStyle(
                    fontFamily: AppTheme.fontUi,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.markInk,
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
              children: achievements.map((ach) {
                return Container(
                  width: 104,
                  margin: const EdgeInsets.only(right: 9),
                  padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 11),
                  decoration: BoxDecoration(
                    color: colors.surf,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: colors.edge2),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: colors.surf2,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(ach["icon"] as IconData, color: ach["color"] as Color, size: 20),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        ach["title"] as String,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: AppTheme.fontUi,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: colors.ink,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityHeatmap(PolotnoColors colors) {
    const days = ["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "ВС"];
    final pattern = [
      1, 2, 1, 0, 3, 2, 1,
      2, 3, 2, 1, 3, 1, 0,
      1, 1, 3, 2, 3, 2, 2,
      0, 2, 1, 3, 3, 1, 2
    ];

    final levels = [
      colors.surf2,
      colors.markSoft,
      colors.mark.withValues(alpha: 0.62),
      colors.mark,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
      child: Column(
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
                "28 ДНЕЙ ПОДРЯД",
                style: TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.1,
                  color: colors.ink3,
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
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    crossAxisSpacing: 5,
                    mainAxisSpacing: 5,
                  ),
                  itemCount: 28,
                  itemBuilder: (context, index) {
                    return Container(
                      decoration: BoxDecoration(
                        color: levels[pattern[index]],
                        borderRadius: BorderRadius.circular(6),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 13),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
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
                    ...levels.map((c) => Container(
                          width: 12,
                          height: 12,
                          margin: const EdgeInsets.only(right: 3),
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        )),
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
          ),
        ],
      ),
    );
  }
}
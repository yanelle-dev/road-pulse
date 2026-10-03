import 'package:flutter/material.dart';
import 'app_theme.dart';

class PotholeDetailsScreen extends StatelessWidget {
  const PotholeDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.asphalt,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(context, colors),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Бейдж силы удара
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: colors.s3Soft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: colors.s3,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "ЖЁСТКО · 32 G",
                          style: TextStyle(
                            fontFamily: AppTheme.fontUi,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: colors.s3,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Заголовок дефекта
                  Text(
                    "Яма в правом ряду",
                    style: TextStyle(
                      fontFamily: AppTheme.fontDisplay,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                      letterSpacing: -1.0,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    "55.75121, 37.61843 · Ленинградский пр-т, 78",
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 11.5,
                      color: colors.ink3,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3 факта
                  _buildFactsGrid(colors),
                  const SizedBox(height: 10),

                  // График профиля удара
                  _buildImpactProfile(colors),
                  const SizedBox(height: 10),

                  // Карточка правила подтверждения DBSCAN
                  _buildConfirmationCard(colors),
                  const SizedBox(height: 10),

                  // Мини-карта дефекта
                  _buildMiniMap(colors),
                  const SizedBox(height: 10),

                  // Кнопки действий
                  _buildActionButtons(colors),
                  const SizedBox(height: 10),

                  // Блок комментариев
                  _buildCommentsSection(colors),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context, PolotnoColors colors) {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      elevation: 0,
      backgroundColor: colors.asphalt,
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: InkWell(
          onTap: () => Navigator.pop(context),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            decoration: BoxDecoration(
              color: colors.glass,
              shape: BoxShape.circle,
              border: Border.all(color: colors.edge),
            ),
            child: Icon(Icons.arrow_back_rounded, color: colors.ink, size: 20),
          ),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.glass,
              shape: BoxShape.circle,
              border: Border.all(color: colors.edge),
            ),
            child: Icon(Icons.share_outlined, color: colors.ink, size: 19),
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: colors.surf2,
              child: Icon(Icons.broken_image_rounded, size: 90, color: colors.ink3),
            ),
            // Градиентная вуаль перехода в фон
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 120,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, colors.asphalt],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            // Точки пагинации фото
            Positioned(
              bottom: 24,
              left: 20,
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 6,
                    decoration: BoxDecoration(
                      color: colors.mark,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: colors.ink.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: colors.ink.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFactsGrid(PolotnoColors colors) {
    return Row(
      children: [
        _buildFactItem(colors, "РАЗМЕР", "L"),
        const SizedBox(width: 8),
        _buildFactItem(colors, "ГЛУБИНА", "~15 см"),
        const SizedBox(width: 8),
        _buildFactItem(colors, "ВОДИТЕЛЕЙ", "12"),
      ],
    );
  }

  Widget _buildFactItem(PolotnoColors colors, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
        decoration: BoxDecoration(
          color: colors.surf,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.edge2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.1,
                color: colors.ink3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontFamily: AppTheme.fontDisplay,
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: colors.ink,
                letterSpacing: -0.6,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImpactProfile(PolotnoColors colors) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: colors.surf,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.edge2),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "ПРОФИЛЬ УДАРА · ОСЬ Z",
                style: TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.2,
                  color: colors.ink3,
                ),
              ),
              Text(
                "пик 8,4 g",
                style: TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.s3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 64,
            width: double.infinity,
            child: CustomPaint(
              painter: ImpactSpikePainter(
                lineColor: colors.s3,
                axisColor: colors.edge,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmationCard(PolotnoColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colors.surf,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.edge2),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: colors.s1, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 12.5,
                  color: colors.ink2,
                  height: 1.45,
                ),
                children: [
                  TextSpan(
                    text: "Подтверждено. ",
                    style: TextStyle(color: colors.ink, fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: "Правило кластеризации: "),
                  TextSpan(
                    text: "≥2 водителя",
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 11.5,
                      color: colors.ink,
                    ),
                  ),
                  const TextSpan(text: " или "),
                  TextSpan(
                    text: "≥3 попадания",
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 11.5,
                      color: colors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMap(PolotnoColors colors) {
    return Container(
      height: 136,
      decoration: BoxDecoration(
        color: colors.voidBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.edge2),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Стилизованная схема дороги
          CustomPaint(
            size: const Size(double.infinity, 136),
            painter: MiniRoadPainter(roadColor: colors.surf),
          ),
          // Точка ямы с ореолом
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colors.s3Soft,
              shape: BoxShape.circle,
            ),
          ),
          Container(
            width: 15,
            height: 15,
            decoration: BoxDecoration(
              color: colors.s3,
              shape: BoxShape.circle,
              border: Border.all(color: colors.asphalt, width: 3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(PolotnoColors colors) {
    return Column(
      children: [
        Row(
          children: [
            _buildActionItem(colors, Icons.navigation_outlined, "Объехать", colors.markInk),
            const SizedBox(width: 8),
            _buildActionItem(colors, Icons.check_rounded, "Она ещё тут", colors.s1),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildActionItem(colors, Icons.build_outlined, "Починили", colors.ink2),
            const SizedBox(width: 8),
            _buildActionItem(colors, Icons.share_outlined, "Поделиться", colors.ink2),
          ],
        ),
      ],
    );
  }

  Widget _buildActionItem(PolotnoColors colors, IconData icon, String label, Color iconColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: colors.surf,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.edge2),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.fontUi,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: colors.ink,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentsSection(PolotnoColors colors) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surf,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.edge2),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Что пишут водители",
                style: TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: colors.ink,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                "24",
                style: TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: 12,
                  color: colors.ink3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildCommentRow(
            colors,
            "МК",
            "Михаил К.",
            "2 ч",
            "После дождя стала глубже, объезжать слева.",
          ),
          Divider(color: colors.edge2, height: 24),
          _buildCommentRow(
            colors,
            "ОП",
            "Ольга П.",
            "5 ч",
            "Проезжала утром — правое колесо ушло целиком.",
          ),
        ],
      ),
    );
  }

  Widget _buildCommentRow(PolotnoColors colors, String initials, String name, String time, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: colors.surf2,
            borderRadius: BorderRadius.circular(11),
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: TextStyle(
              fontFamily: AppTheme.fontUi,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: colors.ink2,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontFamily: AppTheme.fontUi,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    time,
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 10.5,
                      color: colors.ink3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                text,
                style: TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 13,
                  color: colors.ink2,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ImpactSpikePainter extends CustomPainter {
  final Color lineColor;
  final Color axisColor;

  ImpactSpikePainter({required this.lineColor, required this.axisColor});

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1;

    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), axisPaint);

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    final points = [
      Offset(0, midY + 1),
      Offset(size.width * 0.15, midY - 2),
      Offset(size.width * 0.35, midY + 1),
      Offset(size.width * 0.45, midY - 2),
      Offset(size.width * 0.49, 8),
      Offset(size.width * 0.51, size.height - 6),
      Offset(size.width * 0.54, midY - 10),
      Offset(size.width * 0.58, midY + 8),
      Offset(size.width * 0.65, midY - 2),
      Offset(size.width * 0.85, midY + 1),
      Offset(size.width, midY),
    ];

    path.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, linePaint);

    // Точка пика
    final dotPaint = Paint()..color = lineColor;
    canvas.drawCircle(Offset(size.width * 0.49, 8), 3.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MiniRoadPainter extends CustomPainter {
  final Color roadColor;

  MiniRoadPainter({required this.roadColor});

  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = roadColor
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(size.width / 2, -10),
      Offset(size.width / 2, size.height + 10),
      roadPaint,
    );
    canvas.drawLine(
      Offset(-10, size.height / 2),
      Offset(size.width + 10, size.height / 2),
      roadPaint..strokeWidth = 16,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
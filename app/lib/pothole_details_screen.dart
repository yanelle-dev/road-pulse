import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'api_service.dart';
import 'app_theme.dart';
import 'constants.dart';

class PotholeDetailsScreen extends StatefulWidget {
  final Map<String, dynamic>? defect;

  const PotholeDetailsScreen({super.key, this.defect});

  @override
  State<PotholeDetailsScreen> createState() => _PotholeDetailsScreenState();
}

class _PotholeDetailsScreenState extends State<PotholeDetailsScreen> {
  String? _resolvedAddress;
  late Future<List<DefectComment>> _commentsFuture;

  int get _clusterId => ((widget.defect?['cluster_id'] ?? widget.defect?['id'] ?? 0) as num).toInt();
  double? get _lat => (widget.defect?['lat'] ?? widget.defect?['latitude'] as num?)?.toDouble();
  double? get _lon => (widget.defect?['lon'] ?? widget.defect?['longitude'] as num?)?.toDouble();
  double? get _force => (widget.defect?['max_force'] ?? widget.defect?['bump_force'] as num?)?.toDouble();
  String get _defectType => widget.defect?['defect_type']?.toString() ?? 'pothole';
  int get _uniqueUsers => (widget.defect?['unique_users'] as num?)?.toInt() ?? 1;
  int get _totalHits => (widget.defect?['total_hits'] as num?)?.toInt() ?? 1;
  bool get _isConfirmed => widget.defect?['is_confirmed'] == true || _uniqueUsers >= 2 || _totalHits >= 3;

  @override
  void initState() {
    super.initState();
    _resolveAddress();
    _commentsFuture = ApiService.getComments(_clusterId);
  }

  void _reloadComments() {
    setState(() {
      _commentsFuture = ApiService.getComments(_clusterId);
    });
  }

  Future<void> _resolveAddress() async {
    final lat = _lat;
    final lon = _lon;
    if (lat == null || lon == null) return;

    try {
      final placemarks = await Geocoding().placemarkFromCoordinates(lat, lon);
      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        setState(() {
          _resolvedAddress = "${p.street ?? 'Улица'}, ${p.locality ?? 'Москва'}";
        });
      }
    } catch (_) {}
  }

  Future<void> _showAddCommentDialog(PolotnoColors colors) async {
    final textController = TextEditingController();

    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: colors.surf,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            "Комментарий о дефекте",
            style: TextStyle(
              fontFamily: AppTheme.fontDisplay,
              fontSize: 18,
              color: colors.ink,
            ),
          ),
          content: TextField(
            controller: textController,
            maxLines: 3,
            style: TextStyle(fontFamily: AppTheme.fontUi, color: colors.ink),
            decoration: InputDecoration(
              hintText: "Например, яма стала глубже, объезжать справа...",
              hintStyle: TextStyle(color: colors.ink3),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text("Отмена", style: TextStyle(color: colors.ink3)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.mark,
                foregroundColor: colors.onMark,
                elevation: 0,
              ),
              onPressed: () async {
                final txt = textController.text.trim();
                if (txt.isEmpty) return;
                final ok = await ApiService.addComment(clusterId: _clusterId, text: txt);
                if (ctx.mounted) Navigator.pop(ctx, ok);
              },
              child: const Text("Отправить"),
            ),
          ],
        );
      },
    );

    if (added == true && mounted) {
      _reloadComments();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Комментарий успешно добавлен")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final lat = _lat;
    final lon = _lon;
    final force = _force;

    if (lat == null || lon == null || force == null) {
      return Scaffold(
        backgroundColor: colors.asphalt,
        appBar: AppBar(
          backgroundColor: colors.asphalt,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: colors.ink),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_off_outlined, size: 54, color: colors.ink3),
              const SizedBox(height: 16),
              Text(
                "Данные дефекта недоступны",
                style: TextStyle(
                  fontFamily: AppTheme.fontDisplay,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Информация о точке была удалена или не передана",
                style: TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 13,
                  color: colors.ink2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Color levelColor = colors.s1;
    Color levelBg = colors.s1Soft;
    String levelText = "РОВНО";
    String sizeStr = "S";

    if (force > kSeverityHard) {
      levelColor = colors.s3;
      levelBg = colors.s3Soft;
      levelText = "ЖЁСТКО";
      sizeStr = "L";
    } else if (force > kSeverityMedium) {
      levelColor = colors.s2;
      levelBg = colors.s2Soft;
      levelText = "ЗАМЕТНО";
      sizeStr = "M";
    }

    final title = _defectType == 'rough_road'
        ? "Неровная дорога (тряска / колея)"
        : "Дефект дорожного полотна";

    final coordStr = "${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}";
    final addressDisplay = _resolvedAddress != null ? "$coordStr · $_resolvedAddress" : coordStr;

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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: levelBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: levelColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "$levelText · ${force.toStringAsFixed(1)} G",
                          style: TextStyle(
                            fontFamily: AppTheme.fontUi,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: levelColor,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: AppTheme.fontDisplay,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                      letterSpacing: -0.8,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    addressDisplay,
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 11.5,
                      color: colors.ink3,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildFactsGrid(colors, sizeStr, force, _uniqueUsers),
                  const SizedBox(height: 10),
                  _buildImpactProfile(colors, force, levelColor),
                  const SizedBox(height: 10),
                  _buildConfirmationCard(colors, _isConfirmed, _uniqueUsers, _totalHits),
                  const SizedBox(height: 10),
                  _buildMiniMap(colors, isDark, LatLng(lat, lon), levelColor),
                  const SizedBox(height: 10),
                  _buildActionButtons(context, colors),
                  const SizedBox(height: 10),
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
      expandedHeight: 240,
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
          child: InkWell(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Ссылка на дефект скопирована")),
              );
            },
            borderRadius: BorderRadius.circular(999),
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
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: colors.surf2,
              child: Icon(Icons.broken_image_rounded, size: 80, color: colors.ink3),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 100,
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
          ],
        ),
      ),
    );
  }

  Widget _buildFactsGrid(PolotnoColors colors, String sizeStr, double force, int uniqueUsers) {
    return Row(
      children: [
        _buildFactItem(colors, "РАЗМЕР", sizeStr),
        const SizedBox(width: 8),
        _buildFactItem(colors, "СИЛА УДАРА", "${force.toStringAsFixed(1)} G"),
        const SizedBox(width: 8),
        _buildFactItem(colors, "ВОДИТЕЛЕЙ", "$uniqueUsers"),
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
                fontSize: 19,
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

  Widget _buildImpactProfile(PolotnoColors colors, double force, Color levelColor) {
    final peakG = (force / 3.8).toStringAsFixed(1);

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
                "пик $peakG g",
                style: TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: levelColor,
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
                lineColor: levelColor,
                axisColor: colors.edge,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmationCard(PolotnoColors colors, bool isConfirmed, int uniqueUsers, int totalHits) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colors.surf,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.edge2),
      ),
      child: Row(
        children: [
          Icon(
            isConfirmed ? Icons.check_circle_rounded : Icons.pending_outlined,
            color: isConfirmed ? colors.s1 : colors.markInk,
            size: 22,
          ),
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
                children: isConfirmed
                    ? [
                        TextSpan(
                          text: "Подтверждено сообществом. ",
                          style: TextStyle(color: colors.ink, fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: "Правило: ≥2 водителя или ≥3 попадания (зафиксировано: $uniqueUsers вод., $totalHits ударов).",
                        ),
                      ]
                    : [
                        TextSpan(
                          text: "Ожидает подтверждения. ",
                          style: TextStyle(color: colors.markInk, fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: "Нужно: ≥2 водителя или ≥3 попадания (сейчас: $uniqueUsers вод., $totalHits ударов).",
                        ),
                      ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMap(PolotnoColors colors, bool isDark, LatLng point, Color levelColor) {
    return Container(
      height: 160,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.voidBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.edge2),
      ),
      child: FlutterMap(
        options: MapOptions(
          initialCenter: point,
          initialZoom: 15.5,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.roadpulse.app',
            tileBuilder: isDark ? darkModeTileBuilder : null,
          ),
          CircleLayer(
            circles: [
              CircleMarker(
                point: point,
                color: levelColor.withValues(alpha: 0.25),
                useRadiusInMeter: true,
                radius: 35,
              ),
              CircleMarker(
                point: point,
                color: levelColor,
                borderColor: colors.asphalt,
                borderStrokeWidth: 3,
                useRadiusInMeter: true,
                radius: 12,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, PolotnoColors colors) {
    return Column(
      children: [
        Row(
          children: [
            _buildActionItem(
              context,
              colors,
              Icons.navigation_outlined,
              "Объехать",
              colors.markInk,
              () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Маршрут объезда строится...")),
              ),
            ),
            const SizedBox(width: 8),
            _buildActionItem(
              context,
              colors,
              Icons.check_rounded,
              "Она ещё тут",
              colors.s1,
              () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Спасибо! Ваше подтверждение учтено.")),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildActionItem(
              context,
              colors,
              Icons.build_outlined,
              "Починили",
              colors.ink2,
              () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Заявка о ремонте отправлена на проверку.")),
              ),
            ),
            const SizedBox(width: 8),
            _buildActionItem(
              context,
              colors,
              Icons.share_outlined,
              "Поделиться",
              colors.ink2,
              () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Ссылка скопирована в буфер обмена.")),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionItem(
    BuildContext context,
    PolotnoColors colors,
    IconData icon,
    String label,
    Color iconColor,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
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
                    fontSize: 13.0,
                    fontWeight: FontWeight.w600,
                    color: colors.ink,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCommentsSection(PolotnoColors colors) {
    return FutureBuilder<List<DefectComment>>(
      future: _commentsFuture,
      builder: (context, snapshot) {
        final List<DefectComment> comments = snapshot.data ?? const <DefectComment>[];
        final countStr = snapshot.connectionState == ConnectionState.waiting ? "..." : "${comments.length}";

        return Container(
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
                    countStr,
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 12,
                      color: colors.ink3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (comments.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    "Пока нет комментариев. Расскажите другим водителям о состоянии полотна.",
                    style: TextStyle(
                      fontFamily: AppTheme.fontUi,
                      fontSize: 13,
                      color: colors.ink3,
                    ),
                  ),
                )
              else
                ...comments.map((DefectComment c) {
                  final initial = c.authorName.isNotEmpty ? c.authorName[0].toUpperCase() : "В";
                  final timeStr = _formatRelativeTime(c.createdAt);

                  return Column(
                    children: [
                      _buildCommentRow(colors, initial, c.authorName, timeStr, c.text),
                      if (c != comments.last) Divider(color: colors.edge2, height: 24),
                    ],
                  );
                }),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  side: BorderSide(color: colors.edge),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => _showAddCommentDialog(colors),
                icon: Icon(Icons.add_comment_outlined, size: 16, color: colors.markInk),
                label: Text(
                  "Написать комментарий",
                  style: TextStyle(
                    fontFamily: AppTheme.fontUi,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
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

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) {
      return "${diff.inMinutes.clamp(1, 60)} мин назад";
    } else if (diff.inHours < 24) {
      return "${diff.inHours} ч назад";
    }
    return "${diff.inDays} дн назад";
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

    final dotPaint = Paint()..color = lineColor;
    canvas.drawCircle(Offset(size.width * 0.49, 8), 3.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
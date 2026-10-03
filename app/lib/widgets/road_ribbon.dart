import 'package:flutter/material.dart';
import '../app_theme.dart';

class RibbonSegment {
  final double flex;
  final Color color;

  const RibbonSegment({required this.flex, required this.color});
}

/// Виджет «Полоса» — непрерывная дорожная лента качества покрытия
class RoadRibbon extends StatelessWidget {
  final List<RibbonSegment> segments;
  final double height;
  /// Положение маркера «вы здесь» от 0.0 до 1.0 (если null — маркер не рисуется)
  final double? currentPosition;

  const RoadRibbon({
    super.key,
    required this.segments,
    this.height = 14.0,
    this.currentPosition,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Сама лента сегментов
            ClipRRect(
              borderRadius: BorderRadius.circular(height / 2),
              child: SizedBox(
                height: height,
                width: constraints.maxWidth,
                child: Row(
                  children: segments.map((seg) {
                    return Expanded(
                      flex: (seg.flex * 1000).toInt(),
                      child: Container(color: seg.color),
                    );
                  }).toList(),
                ),
              ),
            ),

            // Маркер текущего положения («вы здесь»)
            if (currentPosition != null)
              Positioned(
                left: (constraints.maxWidth * currentPosition!.clamp(0.0, 1.0)) - 1.5,
                top: -4,
                bottom: -4,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: colors.ink,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: colors.surf,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
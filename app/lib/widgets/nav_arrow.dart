import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Маркер «вы здесь» как в навигаторах: стрелка по курсу движения, пока курс неизвестен — точка.
class NavArrow extends StatelessWidget {
  /// Курс в градусах без обнуления на 360°: так анимация поворота идёт кратчайшим путём.
  final double? headingDeg;

  const NavArrow({super.key, required this.headingDeg});

  static const double size = 56;
  static const Size _arrowSize = Size(28, 34);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final heading = headingDeg;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.mark.withValues(alpha: 0.16),
            ),
          ),
          if (heading == null)
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: colors.mark,
                shape: BoxShape.circle,
                border: Border.all(color: colors.asphalt, width: 3),
              ),
            )
          else
            AnimatedRotation(
              turns: heading / 360,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              child: CustomPaint(
                size: _arrowSize,
                painter: _ArrowPainter(fill: colors.mark, outline: colors.asphalt),
              ),
            ),
        ],
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  final Color fill;
  final Color outline;

  const _ArrowPainter({required this.fill, required this.outline});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final tip = Offset(w / 2, 0);
    final right = Offset(w, h);
    final notch = Offset(w / 2, h * 0.72);
    final left = Offset(0, h);

    final body = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(right.dx, right.dy)
      ..lineTo(notch.dx, notch.dy)
      ..lineTo(left.dx, left.dy)
      ..close();
    // Правая половина темнее — стрелка выглядит объёмной.
    final shade = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(right.dx, right.dy)
      ..lineTo(notch.dx, notch.dy)
      ..close();

    canvas.drawShadow(body, Colors.black, 4, false);
    canvas.drawPath(
      body,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(body, Paint()..color = fill);
    canvas.drawPath(shade, Paint()..color = Colors.black.withValues(alpha: 0.16));
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter old) =>
      old.fill != fill || old.outline != outline;
}
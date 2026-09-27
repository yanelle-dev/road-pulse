import 'dart:ui';
import 'package:flutter/material.dart';
import '../app_theme.dart';

class GlassPanel extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;

  const GlassPanel({
    super.key,
    required this.child,
    this.blur = 24.0,
    this.opacity = 0.85,
    this.borderRadius,
    this.padding,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: colors.surf.withValues(alpha: opacity),
            borderRadius: borderRadius,
            border: Border.all(color: colors.edge),
          ),
          child: child,
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';

/// Дизайн-токены системы «Полотно»
class PolotnoColors extends ThemeExtension<PolotnoColors> {
  final Color voidBg;
  final Color asphalt;
  final Color surf;
  final Color surf2;
  final Color edge;
  final Color edge2;

  final Color ink;
  final Color ink2;
  final Color ink3;

  final Color mark;
  final Color markInk;
  final Color onMark;
  final Color markSoft;
  final Color markLine;

  final Color s1;
  final Color s2;
  final Color s3;
  final Color s1Soft;
  final Color s2Soft;
  final Color s3Soft;

  final Color glass;
  final Color glassTab;
  final Color term;

  const PolotnoColors({
    required this.voidBg,
    required this.asphalt,
    required this.surf,
    required this.surf2,
    required this.edge,
    required this.edge2,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.mark,
    required this.markInk,
    required this.onMark,
    required this.markSoft,
    required this.markLine,
    required this.s1,
    required this.s2,
    required this.s3,
    required this.s1Soft,
    required this.s2Soft,
    required this.s3Soft,
    required this.glass,
    required this.glassTab,
    required this.term,
  });

  /// Светлая тема (основа — бетон #EDEDEA, не белый)
  static const light = PolotnoColors(
    voidBg: Color(0xFFEDEDEA),
    asphalt: Color(0xFFF5F5F3),
    surf: Color(0xFFFFFFFF),
    surf2: Color(0xFFE9E9E6),
    edge: Color(0x21101113),
    edge2: Color(0x12101113),
    ink: Color(0xFF101113),
    ink2: Color(0xFF5C6166),
    ink3: Color(0xFF8C9197),
    mark: Color(0xFFFFD21E),
    markInk: Color(0xFF8A6700),
    onMark: Color(0xFF101113),
    markSoft: Color(0x38FFD21E),
    markLine: Color(0x478A6700),
    s1: Color(0xFF17A65C),
    s2: Color(0xFFD96A08),
    s3: Color(0xFFD62B3C),
    s1Soft: Color(0x1F17A65C),
    s2Soft: Color(0x1FD96A08),
    s3Soft: Color(0x1FD62B3C),
    glass: Color(0xCCFFFFFF),
    glassTab: Color(0xE0FFFFFF),
    term: Color(0xFF101113),
  );

  /// Тёмная тема (асфальт и фары #08090A)
  static const dark = PolotnoColors(
    voidBg: Color(0xFF08090A),
    asphalt: Color(0xFF0E1012),
    surf: Color(0xFF16191C),
    surf2: Color(0xFF1F2327),
    edge: Color(0x1AFFFFFF),
    edge2: Color(0x0EFFFFFF),
    ink: Color(0xFFF4F6F7),
    ink2: Color(0xFF98A1A8),
    ink3: Color(0xFF5E666D),
    mark: Color(0xFFFFD21E),
    markInk: Color(0xFFFFD21E),
    onMark: Color(0xFF0E1012),
    markSoft: Color(0x21FFD21E),
    markLine: Color(0x47FFD21E),
    s1: Color(0xFF2FD07A),
    s2: Color(0xFFFF8A34),
    s3: Color(0xFFFF4757),
    s1Soft: Color(0x242FD07A),
    s2Soft: Color(0x24FF8A34),
    s3Soft: Color(0x26FF4757),
    glass: Color(0xD10E1012),
    glassTab: Color(0xDB08090A),
    term: Color(0xFF000000),
  );

  @override
  PolotnoColors copyWith({
    Color? voidBg,
    Color? asphalt,
    Color? surf,
    Color? surf2,
    Color? edge,
    Color? edge2,
    Color? ink,
    Color? ink2,
    Color? ink3,
    Color? mark,
    Color? markInk,
    Color? onMark,
    Color? markSoft,
    Color? markLine,
    Color? s1,
    Color? s2,
    Color? s3,
    Color? s1Soft,
    Color? s2Soft,
    Color? s3Soft,
    Color? glass,
    Color? glassTab,
    Color? term,
  }) {
    return PolotnoColors(
      voidBg: voidBg ?? this.voidBg,
      asphalt: asphalt ?? this.asphalt,
      surf: surf ?? this.surf,
      surf2: surf2 ?? this.surf2,
      edge: edge ?? this.edge,
      edge2: edge2 ?? this.edge2,
      ink: ink ?? this.ink,
      ink2: ink2 ?? this.ink2,
      ink3: ink3 ?? this.ink3,
      mark: mark ?? this.mark,
      markInk: markInk ?? this.markInk,
      onMark: onMark ?? this.onMark,
      markSoft: markSoft ?? this.markSoft,
      markLine: markLine ?? this.markLine,
      s1: s1 ?? this.s1,
      s2: s2 ?? this.s2,
      s3: s3 ?? this.s3,
      s1Soft: s1Soft ?? this.s1Soft,
      s2Soft: s2Soft ?? this.s2Soft,
      s3Soft: s3Soft ?? this.s3Soft,
      glass: glass ?? this.glass,
      glassTab: glassTab ?? this.glassTab,
      term: term ?? this.term,
    );
  }

  @override
  PolotnoColors lerp(ThemeExtension<PolotnoColors>? other, double t) {
    if (other is! PolotnoColors) return this;
    return PolotnoColors(
      voidBg: Color.lerp(voidBg, other.voidBg, t)!,
      asphalt: Color.lerp(asphalt, other.asphalt, t)!,
      surf: Color.lerp(surf, other.surf, t)!,
      surf2: Color.lerp(surf2, other.surf2, t)!,
      edge: Color.lerp(edge, other.edge, t)!,
      edge2: Color.lerp(edge2, other.edge2, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      ink3: Color.lerp(ink3, other.ink3, t)!,
      mark: Color.lerp(mark, other.mark, t)!,
      markInk: Color.lerp(markInk, other.markInk, t)!,
      onMark: Color.lerp(onMark, other.onMark, t)!,
      markSoft: Color.lerp(markSoft, other.markSoft, t)!,
      markLine: Color.lerp(markLine, other.markLine, t)!,
      s1: Color.lerp(s1, other.s1, t)!,
      s2: Color.lerp(s2, other.s2, t)!,
      s3: Color.lerp(s3, other.s3, t)!,
      s1Soft: Color.lerp(s1Soft, other.s1Soft, t)!,
      s2Soft: Color.lerp(s2Soft, other.s2Soft, t)!,
      s3Soft: Color.lerp(s3Soft, other.s3Soft, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      glassTab: Color.lerp(glassTab, other.glassTab, t)!,
      term: Color.lerp(term, other.term, t)!,
    );
  }
}

/// Удобный доступ к токенам через context.colors
extension PolotnoThemeContext on BuildContext {
  PolotnoColors get colors =>
      Theme.of(this).extension<PolotnoColors>() ?? PolotnoColors.light;
}

class AppTheme {
  static const String fontUi = 'Onest';
  static const String fontDisplay = 'Unbounded';
  static const String fontMono = 'JetBrains Mono';

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: PolotnoColors.light.voidBg,
      fontFamily: fontUi,
      extensions: const [PolotnoColors.light],
      colorScheme: ColorScheme.light(
        surface: PolotnoColors.light.surf,
        primary: PolotnoColors.light.mark,
        onPrimary: PolotnoColors.light.onMark,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: PolotnoColors.dark.voidBg,
      fontFamily: fontUi,
      extensions: const [PolotnoColors.dark],
      colorScheme: ColorScheme.dark(
        surface: PolotnoColors.dark.surf,
        primary: PolotnoColors.dark.mark,
        onPrimary: PolotnoColors.dark.onMark,
      ),
    );
  }
}
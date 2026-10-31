import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../main.dart' show themeModeNotifier;

/// Сегментированный переключатель темы: «Система / Светлая / Тёмная».
class ThemeModeSelector extends StatelessWidget {
  const ThemeModeSelector({super.key});

  static const _options = <(ThemeMode, String, IconData)>[
    (ThemeMode.system, 'Система', Icons.brightness_auto_rounded),
    (ThemeMode.light, 'Светлая', Icons.light_mode_rounded),
    (ThemeMode.dark, 'Тёмная', Icons.dark_mode_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colors.surf2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.edge2),
        ),
        child: Row(
          children: [
            for (final (value, label, icon) in _options)
              Expanded(
                child: _Segment(
                  label: label,
                  icon: icon,
                  selected: mode == value,
                  onTap: () => themeModeNotifier.value = value,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = selected ? colors.onMark : colors.ink2;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? colors.mark : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'map_screen.dart';
import 'list_screen.dart';
import 'detect_screen.dart';
import 'profile_screen.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  static MainScaffoldState? of(BuildContext context) =>
      context.findAncestorStateOfType<MainScaffoldState>();

  @override
  State<MainScaffold> createState() => MainScaffoldState();
}

class MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  void switchTab(int index) {
    if (index >= 0 && index < 4) {
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      MapScreen(onNavigateToTab: switchTab),
      const ListScreen(),
      const DetectScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    final colors = context.colors;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: 86,
          decoration: BoxDecoration(
            color: colors.glassTab,
            border: Border(
              top: BorderSide(color: colors.edge, width: 1),
            ),
          ),
          child: Row(
            children: [
              _buildNavItem(0, Icons.map_outlined, "Карта"),
              _buildNavItem(1, Icons.format_list_bulleted_rounded, "Дефекты"),
              _buildNavItem(2, Icons.show_chart_rounded, "Запись"),
              _buildNavItem(3, Icons.person_outline, "Профиль"),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final colors = context.colors;
    final isActive = _currentIndex == index;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => switchTab(index),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 24,
                color: isActive ? colors.markInk : colors.ink3,
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isActive ? colors.markInk : colors.ink3,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';
import 'fresh_prefs.dart';

/// Хранение выбранного режима темы между запусками.
class ThemeStore {
  static Future<ThemeMode> load() async {
    final prefs = await freshPrefs();
    return ThemeMode.values.asNameMap()[prefs.getString(kKeyThemeMode)] ?? ThemeMode.system;
  }

  static Future<void> save(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kKeyThemeMode, mode.name);
  }
}
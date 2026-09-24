import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// الوضع الداكن أساسي (ق38)؛ الفاتح متاح للاختيار ويُحفظ في تفضيلات الجهاز.
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController() : super(ThemeMode.dark) {
    _load();
  }

  static const _key = 'saloni_theme_mode';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved == 'light') state = ThemeMode.light;
    } catch (_) {
      // تجاهل — الوضع الداكن الافتراضي يبقى ساريًا.
    }
  }

  Future<void> toggle() async {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, state == ThemeMode.dark ? 'dark' : 'light');
    } catch (_) {}
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) => ThemeModeController());

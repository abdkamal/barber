import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';

/// تفضيلات غير سرية على الجهاز (المظهر، الجولة التعريفية، آخر رمز صالون...).
/// الأسرار (رموز الجلسة، مفتاح القاعدة) في التخزين الآمن فقط.
class AppPrefs extends ChangeNotifier {
  AppPrefs(this._p) {
    // ق41: أُلغي خيار «الأرقام العربية المشرقية» — الأرقام غربية دائمًا.
    // يُحذف التفضيل القديم إن وُجد (دون انتظار؛ لا يؤثر شيء على قيمته).
    if (_p.containsKey('easternDigits')) _p.remove('easternDigits');
  }

  final SharedPreferences _p;

  static Future<AppPrefs> load() async =>
      AppPrefs(await SharedPreferences.getInstance());

  ThemeMode get themeMode =>
      _p.getString('theme') == 'light' ? ThemeMode.light : ThemeMode.dark;

  Future<void> setThemeMode(ThemeMode m) async {
    await _p.setString('theme', m == ThemeMode.light ? 'light' : 'dark');
    notifyListeners();
  }

  bool onboardingSeen(String role) => _p.getBool('onboarding_$role') ?? false;

  Future<void> setOnboardingSeen(String role, bool v) async {
    await _p.setBool('onboarding_$role', v);
    notifyListeners();
  }

  bool get notificationCheckDone => _p.getBool('notifCheckDone') ?? false;
  Future<void> setNotificationCheckDone() => _p.setBool('notifCheckDone', true);

  String? get lastSalonCode => _p.getString('lastSalonCode');
  String? get lastUsername => _p.getString('lastUsername');

  Future<void> rememberLogin(String code, String username) async {
    await _p.setString('lastSalonCode', code);
    await _p.setString('lastUsername', username);
  }

  SalonMeta? get salon {
    final raw = _p.getString('salonMeta');
    if (raw == null) return null;
    try {
      return SalonMeta.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> setSalon(SalonMeta? s) async {
    if (s == null) {
      await _p.remove('salonMeta');
    } else {
      await _p.setString('salonMeta', jsonEncode(s.toJson()));
    }
  }

  String? get accountName => _p.getString('accountName');
  Future<void> setAccountName(String? v) async =>
      v == null ? _p.remove('accountName') : _p.setString('accountName', v);

  /// صاحب البيانات المحلية (رمز الصالون|اسم المستخدم) — لمسحها إن دخل حساب آخر.
  String? get storeOwner => _p.getString('storeOwner');
  Future<void> setStoreOwner(String? v) async =>
      v == null ? _p.remove('storeOwner') : _p.setString('storeOwner', v);
}

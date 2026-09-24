import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/salon_session.dart';

/// يحفظ حسابات الزبون لكل صالون أضافه على هذا الجهاز (ق7: صالون واحد بحساب
/// مستقل). الجلسات (تحمل رمز التجديد) في التخزين الآمن؛ رمز الصالون النشط في
/// تفضيلات عادية (لا يحمل سرًا).
class MultiSalonStore {
  MultiSalonStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const _salonsKey = 'saloni_customer_salons_v1';
  static const _activeKey = 'saloni_customer_active_salon';

  final FlutterSecureStorage _storage;
  List<SalonSession>? _cache;

  Future<List<SalonSession>> loadAll() async {
    if (_cache != null) return _cache!;
    final raw = await _storage.read(key: _salonsKey);
    if (raw == null || raw.isEmpty) {
      _cache = [];
      return _cache!;
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _cache = list
          .map((e) => SalonSession.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _cache = [];
    }
    return _cache!;
  }

  Future<void> _persist() async {
    final list = _cache ?? [];
    await _storage.write(
      key: _salonsKey,
      value: jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  /// يحفظ/يحدّث جلسة صالون واحد. إذا كان `rememberMe == false` لا يُخزَّن على
  /// القرص، فقط في الذاكرة لهذه الجلسة (ق17).
  Future<void> upsert(SalonSession salonSession, {required bool rememberMe}) async {
    await loadAll();
    _cache!.removeWhere((e) => e.code == salonSession.code);
    _cache!.add(salonSession);
    if (rememberMe) {
      await _persist();
    }
  }

  Future<void> remove(String code) async {
    await loadAll();
    _cache!.removeWhere((e) => e.code == code);
    await _persist();
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_activeKey) == code) {
      await prefs.remove(_activeKey);
    }
  }

  Future<SalonSession?> get(String code) async {
    final all = await loadAll();
    for (final s in all) {
      if (s.code == code) return s;
    }
    return null;
  }

  Future<void> setActiveCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeKey, code);
  }

  Future<String?> activeCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeKey);
  }

  Future<void> clearActive() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeKey);
  }
}

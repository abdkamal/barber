/// أجزاء تعتمد على Flutter — نقطة دخول منفصلة كي تبقى `saloni_api.dart`
/// (النواة) قابلة للاختبار عبر `dart test` بلا SDK فلاتر.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';

import 'src/models/session.dart';
import 'src/token_store.dart';

/// مخزن جلسة فوق `flutter_secure_storage` — ق17: «الدخول تلقائيًا» يحفظ رمز
/// التجديد على الجهاز؛ غير ذلك يبقى في الذاكرة فقط.
///
/// عند `persist: false` تُبقي النسخة في الذاكرة فقط ولا تُكتب على القرص (وتُمسح
/// أي نسخة سابقة محفوظة)، بحيث لا يُعاد فتح الجلسة تلقائيًا بعد إغلاق التطبيق
/// إن لم يطلب المستخدم ذلك.
class SecureStorageTokenStore implements TokenStore {
  SecureStorageTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _key = 'saloni_session_v1';

  final FlutterSecureStorage _storage;
  Session? _memorySession;

  @override
  Future<Session?> read() async {
    if (_memorySession != null) return _memorySession;
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      return Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await _storage.delete(key: _key);
      return null;
    }
  }

  @override
  Future<void> save(Session session, {required bool persist}) async {
    _memorySession = session;
    if (persist) {
      await _storage.write(key: _key, value: jsonEncode(session.toJson()));
    } else {
      await _storage.delete(key: _key);
    }
  }

  @override
  Future<void> clear() async {
    _memorySession = null;
    await _storage.delete(key: _key);
  }
}

/// يقرأ مفتاح تشفير قاعدة الطاقم المحلية من التخزين الآمن، أو يولّده ويحفظه
/// عند أول استخدام (design.md §6.1، §7 «الجهاز: قاعدة محلية مشفرة»).
/// المفتاح منفصل عن رمز التجديد ولا يُمسح بمسح الجلسة وحدها، بل عند
/// `wipeStaffSyncEncryptionKey` (يُستدعى مع مسح قاعدة البيانات عند الخروج).
Future<String> staffSyncEncryptionKey({FlutterSecureStorage? storage}) async {
  final s = storage ?? const FlutterSecureStorage();
  const keyName = 'saloni_staff_db_key_v1';
  final existing = await s.read(key: keyName);
  if (existing != null) return existing;
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  final generated = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  await s.write(key: keyName, value: generated);
  return generated;
}

Future<void> wipeStaffSyncEncryptionKey({FlutterSecureStorage? storage}) async {
  final s = storage ?? const FlutterSecureStorage();
  await s.delete(key: 'saloni_staff_db_key_v1');
}

/// يفتح منفّذ استعلام Drift مشفّرًا بـSQLCipher لقاعدة الطاقم المحلية
/// (design.md §6.1). يستخدم `sqlcipher_flutter_libs` لتوفير مكتبة sqlite3
/// المبنية بدعم SQLCipher على أندرويد/iOS.
///
/// **ملاحظة صدق:** هذا المسار لم يُختبر فعليًا على جهاز/محاكي — لا يوجد
/// Android SDK في بيئة التطوير الحالية (`docs/environment.md`). المنطق مبني
/// على نمط الدمج الموثّق رسميًا بين `drift` و`sqlcipher_flutter_libs`
/// (`PRAGMA key` عند فتح الاتصال)، ويجب التحقق منه على جهاز حقيقي في مرحلة
/// تجربة نسخة التطوير قبل الاعتماد عليه.
QueryExecutor openEncryptedStaffSyncExecutor({
  required String fileName,
  required String encryptionKey,
}) {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$fileName');
    open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
    return NativeDatabase.createInBackground(
      file,
      setup: (rawDb) {
        rawDb.execute("PRAGMA key = '$encryptionKey';");
      },
    );
  });
}

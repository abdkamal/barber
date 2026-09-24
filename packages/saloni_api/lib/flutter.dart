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
/// **إصلاح تجربة المرحلة 11:** القاعدة تعمل في **عزلة (isolate) خلفية**
/// (`createInBackground`)، و`open.overrideFor` متغير عام لا ينتقل إلى العزلات
/// الأخرى. كان التجاوز يُطبَّق في العزلة الرئيسية فقط، فتحاول العزلة الخلفية
/// تحميل `libsqlite3.so` — غير موجود في الحزمة (فيها `libsqlcipher.so` فقط) —
/// فيفشل **كل** تسجيل محلي على الهاتف («تعذّر التسجيل: حدث خطأ غير متوقع»).
/// الآن يُطبَّق التجاوز داخل العزلة الخلفية (`isolateSetup`) ويُتحقق من أن
/// المكتبة المحمّلة هي SQLCipher فعلًا (`PRAGMA cipher_version`)، فلا تُنشأ
/// قاعدة غير مشفرة بصمت.
QueryExecutor openEncryptedStaffSyncExecutor({
  required String fileName,
  required String encryptionKey,
}) {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$fileName');
    await _useSqlCipher();
    return NativeDatabase.createInBackground(
      file,
      isolateSetup: _useSqlCipher,
      setup: (rawDb) {
        final version = rawDb.select('PRAGMA cipher_version;');
        if (version.isEmpty || version.first.values.first == null) {
          throw StateError('SQLCipher غير متاح — لا تُفتح القاعدة المحلية دون تشفير');
        }
        rawDb.execute("PRAGMA key = '$encryptionKey';");
      },
    );
  });
}

/// يوجّه `package:sqlite3` إلى مكتبة SQLCipher المرفقة (أندرويد). يُستدعى في
/// العزلة الرئيسية **وفي** عزلة القاعدة الخلفية (دالة عليا لا تلتقط حالة).
Future<void> _useSqlCipher() async {
  if (Platform.isAndroid) {
    open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
  }
}

import 'models/session.dart';

/// مخزن جلسة الدخول. التطبيق الأساسي (pure Dart) يوفّر تنفيذًا في الذاكرة
/// فقط؛ `lib/flutter.dart` يوفّر تنفيذًا آمنًا فوق `flutter_secure_storage`
/// (ق17: «الدخول تلقائيًا» = حفظ رمز التجديد في التخزين الآمن).
abstract class TokenStore {
  /// يقرأ الجلسة المحفوظة إن وُجدت.
  Future<Session?> read();

  /// يحفظ الجلسة. إذا كان `persist == false` يُحتفظ بها في الذاكرة فقط
  /// لهذه الجلسة (لا "دخول تلقائي").
  Future<void> save(Session session, {required bool persist});

  /// يمسح كل ما هو محفوظ (تسجيل خروج).
  Future<void> clear();
}

/// تنفيذ في الذاكرة فقط — للاختبارات وللاستخدام حين لا يُطلب "دخول تلقائي".
class InMemoryTokenStore implements TokenStore {
  Session? _session;

  @override
  Future<Session?> read() async => _session;

  @override
  Future<void> save(Session session, {required bool persist}) async {
    _session = session;
  }

  @override
  Future<void> clear() async {
    _session = null;
  }
}

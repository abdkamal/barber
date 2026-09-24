import 'package:customer/models/salon_session.dart';
import 'package:customer/services/multi_salon_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_api/saloni_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

Session _sessionFor(String code, String refreshToken) => Session(
      accessToken: 'access-$code',
      refreshToken: refreshToken,
      role: UserRole.customer,
      salon: SalonInfo(code: code, name: 'صالون $code', status: 'active', currency: 'SAR'),
      account: const AccountInfo(id: 'c-1', name: 'سالم', status: 'active'),
    );

Session _session() => Session(
      accessToken: 'access',
      refreshToken: 'refresh-token-1',
      role: UserRole.customer,
      salon: const SalonInfo(code: 'RAHA-27', name: 'صالون الراحة', status: 'active', currency: 'SAR'),
      account: const AccountInfo(id: 'c-1', name: 'سالم', status: 'active'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // «قرص» مشترك تحاكيه هذه الخريطة — يبقى بين إعادة إنشاء `MultiSalonStore`
  // لمحاكاة إعادة تشغيل التطبيق (ذاكرة `_cache` تُفقد، والقرص يبقى).
  late Map<String, String> disk;

  MultiSalonStore freshStore() {
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(disk);
    return MultiSalonStore(storage: const FlutterSecureStorage());
  }

  setUp(() {
    disk = {};
    SharedPreferences.setMockInitialValues({});
  });

  test('L7: rememberMe=false لا يُخزَّن على القرص (يبقى في الذاكرة فقط)', () async {
    final store = freshStore();
    await store.upsert(
      SalonSession(code: 'RAHA-27', name: 'صالون الراحة', session: _session()),
      rememberMe: false,
    );

    // في نفس التشغيل: الجلسة متاحة من الذاكرة.
    expect((await store.get('RAHA-27'))?.session.refreshToken, 'refresh-token-1');

    // بعد «إعادة تشغيل» التطبيق (مقبض جديد بلا ذاكرة سابقة): لا شيء على القرص.
    final restarted = freshStore();
    expect(await restarted.get('RAHA-27'), isNull);
  });

  test('L7: rememberMe=false يحذف أي جلسة أقدم كانت محفوظة على القرص لنفس الصالون', () async {
    final store = freshStore();
    // أول دخول: «الدخول تلقائيًا» مفعّل — تُحفظ الجلسة على القرص.
    await store.upsert(
      SalonSession(code: 'RAHA-27', name: 'صالون الراحة', session: _session()),
      rememberMe: true,
    );
    expect(disk, isNotEmpty);

    // دخول لاحق لنفس الصالون بلا «تذكّرني» — يجب ألا يبقى رمز التجديد القديم
    // قابلًا للاسترجاع من القرص بعد إعادة التشغيل.
    final secondSession = Session(
      accessToken: 'access-2',
      refreshToken: 'refresh-token-2',
      role: UserRole.customer,
      salon: const SalonInfo(code: 'RAHA-27', name: 'صالون الراحة', status: 'active', currency: 'SAR'),
      account: const AccountInfo(id: 'c-1', name: 'سالم', status: 'active'),
    );
    await store.upsert(
      SalonSession(code: 'RAHA-27', name: 'صالون الراحة', session: secondSession),
      rememberMe: false,
    );

    final restarted = freshStore();
    expect(await restarted.get('RAHA-27'), isNull,
        reason: 'لا رمز تجديد (قديم أو جديد) يجب أن يبقى صالحًا على القرص');
  });

  test('rememberMe=true يبقى محفوظًا على القرص بعد إعادة التشغيل', () async {
    final store = freshStore();
    await store.upsert(
      SalonSession(code: 'RAHA-27', name: 'صالون الراحة', session: _session()),
      rememberMe: true,
    );
    final restarted = freshStore();
    expect((await restarted.get('RAHA-27'))?.session.refreshToken, 'refresh-token-1');
  });

  test(
      'L7 (متبقٍّ): صالونان — تجديد جلسة الصالون المتذكَّر لا يكتب رمز تجديد '
      'الصالون غير المتذكَّر إلى القرص', () async {
    final store = freshStore();

    // صالون A: «الدخول تلقائيًا» مفعّل.
    await store.upsert(
      SalonSession(code: 'A-01', name: 'صالون أ', session: _sessionFor('A-01', 'a-refresh-1')),
      rememberMe: true,
    );
    // صالون B: بلا «تذكّرني» — يبقى في الذاكرة فقط لهذا التشغيل.
    await store.upsert(
      SalonSession(code: 'B-02', name: 'صالون ب', session: _sessionFor('B-02', 'b-refresh-1')),
      rememberMe: false,
    );

    // كلا الصالونين متاحان من الذاكرة في هذا التشغيل.
    expect((await store.get('A-01'))?.session.refreshToken, 'a-refresh-1');
    expect((await store.get('B-02'))?.session.refreshToken, 'b-refresh-1');

    // صالون A يجدّد جلسته (رمز تجديد جديد) بينما B لا يزال في الذاكرة —
    // يجب ألا يكتب هذا رمز B على القرص رغم أن كلا الصالونين في `_cache`.
    await store.upsert(
      SalonSession(code: 'A-01', name: 'صالون أ', session: _sessionFor('A-01', 'a-refresh-2')),
      rememberMe: true,
    );

    final restarted = freshStore();
    expect((await restarted.get('A-01'))?.session.refreshToken, 'a-refresh-2',
        reason: 'صالون A متذكَّر ويحمل آخر رمز تجديد');
    expect(await restarted.get('B-02'), isNull,
        reason: 'رمز تجديد صالون B غير المتذكَّر يجب ألا يظهر على القرص أبدًا، '
            'ولو تجدّدت جلسة صالون آخر');
  });

  test('L7 (متبقٍّ): remove() لا يكتب على القرص جلسة صالون آخر غير متذكَّر',
      () async {
    final store = freshStore();
    await store.upsert(
      SalonSession(code: 'A-01', name: 'صالون أ', session: _sessionFor('A-01', 'a-refresh-1')),
      rememberMe: true,
    );
    await store.upsert(
      SalonSession(code: 'B-02', name: 'صالون ب', session: _sessionFor('B-02', 'b-refresh-1')),
      rememberMe: false,
    );

    // إزالة صالون A من هذا الجهاز (حساب انتهى مثلًا) تُعيد كتابة القرص —
    // يجب ألا تُسرّب معها رمز تجديد B غير المتذكَّر.
    await store.remove('A-01');

    final restarted = freshStore();
    expect(await restarted.get('A-01'), isNull);
    expect(await restarted.get('B-02'), isNull,
        reason: 'B لم يكن متذكَّرًا أصلًا — يجب ألا يظهر على القرص بعد remove() لصالون آخر');
  });
}

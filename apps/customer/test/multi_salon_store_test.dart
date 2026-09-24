import 'package:customer/models/salon_session.dart';
import 'package:customer/services/multi_salon_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_api/saloni_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:saloni_api/saloni_api.dart' as sa;

import '../core/compat_http_client.dart';
import '../core/config.dart';
import '../core/format.dart';
import '../core/platform/device_services.dart';
import '../core/platform/push.dart';
import '../core/platform/storage.dart';
import '../core/prefs.dart';
import '../core/raw_api.dart';
import '../data/barber_repository.dart';
import '../data/models.dart';

/// الخدمات المشتركة للتطبيق — تُبنى في `main` وتُستبدل في الاختبارات.
class AppServices {
  AppServices({
    required this.api,
    required this.compat,
    required this.raw,
    required this.storage,
    required this.device,
    required this.push,
    required this.prefs,
    this.heartbeat = AppConfig.heartbeat,
  });

  final sa.ApiClient api;
  final CompatHttpClient compat;
  final RawApi raw;
  final StoragePlatform storage;
  final DeviceServices device;
  final PushService push;
  final AppPrefs prefs;
  final Duration heartbeat;

  static Future<AppServices> create() async {
    final prefs = await AppPrefs.load();
    final storage = defaultStoragePlatform();
    return AppServices.build(
      baseUrl: AppConfig.apiBaseUrl,
      inner: http.Client(),
      storage: storage,
      device: defaultDeviceServices(),
      push: defaultPushService(),
      prefs: prefs,
    );
  }

  factory AppServices.build({
    required String baseUrl,
    required http.Client inner,
    required StoragePlatform storage,
    required DeviceServices device,
    required PushService push,
    required AppPrefs prefs,
    Duration heartbeat = AppConfig.heartbeat,
  }) {
    final compat = CompatHttpClient(inner);
    final api = sa.ApiClient(
      baseUrl: baseUrl,
      tokenStore: storage.createTokenStore(),
      httpClient: compat,
    );
    return AppServices(
      api: api,
      compat: compat,
      raw: RawApi(api: api, http_: compat, baseUrl: baseUrl),
      storage: storage,
      device: device,
      push: push,
      prefs: prefs,
      heartbeat: heartbeat,
    );
  }
}

final servicesProvider = Provider<AppServices>(
  (ref) => throw UnimplementedError('servicesProvider must be overridden'),
);

final prefsProvider = ChangeNotifierProvider<AppPrefs>(
  (ref) => ref.watch(servicesProvider).prefs,
);

enum AuthStatus { unknown, signedOut, signedIn }

/// حالة الدخول والجلسة (ق17، ق18).
class AuthController extends ChangeNotifier {
  AuthController(this.services) {
    services.compat.onSessionMeta = _onMeta;
    services.api.onSignedOut.listen((_) => _forcedSignOut());
  }

  final AppServices services;
  AuthStatus status = AuthStatus.unknown;
  sa.UserRole? role;
  SalonMeta? salon;
  String? accountName;

  /// يتغير مع كل دخول/خروج — مفتاح إعادة بناء مستودع الطابور.
  int sessionKey = 0;

  bool get isManager => role == sa.UserRole.manager;
  Currency get currency => Currency.of(salon?.currency);

  void _onMeta(Map<String, dynamic>? salonJson, Map<String, dynamic>? account) {
    if (salonJson != null) {
      salon = SalonMeta.fromJson(salonJson);
      services.prefs.setSalon(salon);
    }
    if (account != null && account['name'] != null) {
      accountName = account['name'].toString();
      services.prefs.setAccountName(accountName);
    }
  }

  Future<void> bootstrap() async {
    try {
      final s = await services.api.restoreSession();
      if (s != null && s.role != sa.UserRole.customer) {
        role = s.role;
        salon = services.prefs.salon ?? SalonMeta(code: s.salonCode);
        accountName = services.prefs.accountName;
        status = AuthStatus.signedIn;
        sessionKey++;
      } else {
        status = AuthStatus.signedOut;
      }
    } catch (_) {
      status = AuthStatus.signedOut;
    }
    notifyListeners();
  }

  /// دخول الطاقم: رمز الصالون + اسم المستخدم + كلمة المرور (§7).
  Future<void> login({
    required String salonCode,
    required String username,
    required String password,
    required bool rememberMe,
  }) async {
    final code = salonCode.trim().toUpperCase();
    final user = username.trim();
    final session = await services.api.loginStaff(
      salonCode: code,
      username: user,
      password: password,
      rememberMe: rememberMe,
    );
    if (session.role == sa.UserRole.customer) {
      await services.api.logout();
      throw const sa.ApiError(
        code: 'NOT_STAFF',
        message: 'هذا التطبيق للطاقم فقط. استخدم تطبيق «صالوني» للزبائن.',
      );
    }
    await _adoptOwner('${session.salonCode}|$user');
    await services.prefs.rememberLogin(code, user);
    role = session.role;
    salon ??= SalonMeta(code: session.salonCode);
    status = AuthStatus.signedIn;
    sessionKey++;
    notifyListeners();
  }

  /// يحدّث بيانات الصالون (مثل انتهاء «بانتظار التفعيل») من `GET /auth/session`.
  Future<void> refreshSessionInfo() async {
    try {
      final r = await services.raw.send('GET', '/auth/session');
      if (r is Map && r['salon'] is Map) {
        salon = SalonMeta.fromJson(Map<String, dynamic>.from(r['salon'] as Map));
        await services.prefs.setSalon(salon);
        notifyListeners();
      }
    } catch (_) {}
  }

  /// ق37: تسجيل صالون جديد — يعيد رمز الصالون. المالك يدخل كمدير مباشرة.
  Future<String> registerSalon({
    required Map<String, dynamic> salonData,
    required Map<String, dynamic> owner,
  }) async {
    final json = await services.api.registerSalon({'salon': salonData, 'owner': owner});
    final sessionJson = json['session'];
    final salonJson = json['salon'];
    final code = salonJson is Map ? salonJson['code'].toString() : '';
    if (sessionJson is Map<String, dynamic>) {
      final session = sa.Session.fromJson(sessionJson);
      await services.api.setSession(session, rememberMe: true);
      await _adoptOwner('${session.salonCode}|${owner['username']}');
      await services.prefs.rememberLogin(session.salonCode, owner['username'].toString());
      role = session.role;
      salon ??= SalonMeta(code: session.salonCode, status: 'pending_activation');
    }
    return code;
  }

  /// بعد شاشة «بانتظار التفعيل»: الانتقال إلى التطبيق بالجلسة الجديدة.
  void enterAfterSignup() {
    if (role == null) return;
    status = AuthStatus.signedIn;
    sessionKey++;
    notifyListeners();
  }

  /// إن دخل حساب مختلف على هذا الجهاز تُمسح بيانات الحساب السابق (§6.1).
  Future<void> _adoptOwner(String owner) async {
    final prev = services.prefs.storeOwner;
    if (prev != null && prev != owner) {
      final h = await services.storage.openLocalStore();
      await h.destroy();
    }
    await services.prefs.setStoreOwner(owner);
  }

  /// خروج اختياري: يُستدعى بعد مسح مستودع الطابور (انظر `signOut`).
  Future<void> logout() async {
    await services.api.logout();
    await services.prefs.setSalon(null);
    await services.prefs.setAccountName(null);
    await services.prefs.setStoreOwner(null);
    _clear();
  }

  /// انتهت الجلسة (فشل التجديد): نعود لشاشة الدخول دون مسح الأحداث غير
  /// المُزامنة؛ تُرسل بعد دخول الحساب نفسه، وتُمسح إن دخل حساب آخر.
  void _forcedSignOut() {
    if (status != AuthStatus.signedIn) return;
    _clear();
  }

  void _clear() {
    role = null;
    salon = null;
    accountName = null;
    status = AuthStatus.signedOut;
    sessionKey++;
    notifyListeners();
  }
}

final authProvider = ChangeNotifierProvider<AuthController>(
  (ref) => AuthController(ref.watch(servicesProvider)),
);

/// مستودع طابور الحلاق للجلسة الحالية — يُعاد بناؤه مع كل دخول.
final barberRepoProvider = ChangeNotifierProvider<BarberRepository>((ref) {
  ref.watch(authProvider.select((a) => a.sessionKey));
  final services = ref.watch(servicesProvider);
  final auth = ref.read(authProvider);
  final repo = BarberRepository(
    api: services.api,
    compat: services.compat,
    openStore: services.storage.openLocalStore,
    device: services.device,
    currency: auth.currency,
    heartbeat: services.heartbeat,
  );
  if (auth.status == AuthStatus.signedIn) {
    repo.start();
  }
  return repo;
});

/// الخروج الكامل: مسح الطابور المحلي والمفتاح، ثم إلغاء الجلسة.
Future<void> signOut(WidgetRef ref) async {
  final auth = ref.read(authProvider);
  final services = ref.read(servicesProvider);
  try {
    if (ref.exists(barberRepoProvider)) {
      await ref.read(barberRepoProvider).wipeAll();
    } else {
      await (await services.storage.openLocalStore()).destroy();
      await services.device.stopKeepAlive();
    }
  } catch (e) {
    debugPrint('wipe failed: $e');
  }
  await auth.logout();
}

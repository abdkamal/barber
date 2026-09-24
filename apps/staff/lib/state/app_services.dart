import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:saloni_api/saloni_api.dart' as sa;

import '../core/config.dart';
import '../core/format.dart';
import '../core/platform/device_services.dart';
import '../core/platform/push.dart';
import '../core/platform/storage.dart';
import '../core/prefs.dart';
import '../data/barber_repository.dart';
import '../data/models.dart';

/// الخدمات المشتركة للتطبيق — تُبنى في `main` وتُستبدل في الاختبارات.
class AppServices {
  AppServices({
    required this.api,
    required this.storage,
    required this.device,
    required this.push,
    required this.prefs,
    this.heartbeat = AppConfig.heartbeat,
  });

  final sa.ApiClient api;
  final StoragePlatform storage;
  final DeviceServices device;
  final PushService push;
  final AppPrefs prefs;
  final Duration heartbeat;

  /// مقبض التخزين المحلي المفتوح حاليًا (إن وُجد) — يضمن عدم فتح مقبض ثانٍ
  /// متزامن على نفس قاعدة SQLCipher عند الإغلاق القسري أو المسح (انظر
  /// `openLocalStore`/`closeActiveHandle`/`destroyLocalStore`).
  LocalStoreHandle? activeHandle;

  /// يغلق أي مقبض سابق أولًا (دفاعيًا) ثم يفتح مقبضًا جديدًا ويتتبعه.
  Future<LocalStoreHandle> openLocalStore() async {
    await closeActiveHandle();
    final h = await storage.openLocalStore();
    activeHandle = h;
    return h;
  }

  /// يغلق المقبض النشط دون مسح بياناته (خروج قسري لا يعني فقدان الصندوق).
  Future<void> closeActiveHandle() async {
    final h = activeHandle;
    activeHandle = null;
    if (h != null) {
      try {
        await h.close();
      } catch (_) {}
    }
  }

  /// يمسح التخزين المحلي: يغلق ويمسح المقبض النشط مباشرة إن وُجد (لا يفتح
  /// مقبضًا ثانيًا بينما الأول ما زال قد يكون مفتوحًا)، وإلا يفتح مقبضًا واحدًا
  /// جديدًا ليمسحه.
  Future<void> destroyLocalStore() async {
    final h = activeHandle;
    activeHandle = null;
    if (h != null) {
      await h.destroy();
      return;
    }
    final fresh = await storage.openLocalStore();
    await fresh.destroy();
  }

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
    final api = sa.ApiClient(
      baseUrl: baseUrl,
      tokenStore: storage.createTokenStore(),
      httpClient: inner,
    );
    return AppServices(
      api: api,
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
    services.api.onSignedOut.listen((_) => _forcedSignOut());
  }

  final AppServices services;
  AuthStatus status = AuthStatus.unknown;
  sa.UserRole? role;
  SalonMeta? salon;
  String? accountName;

  /// يتغير مع كل دخول/خروج — مفتاح إعادة بناء مستودع الطابور.
  int sessionKey = 0;

  /// عدد إجراءات الصندوق التي لم تُزامن بعد، محفوظة من آخر خروج قسري (جلسة
  /// أُبطلت لا حساب أُوقف) — تُعرض للحلاق في شاشة الدخول ليعرف أن بياناته لم
  /// تُفقد. تُصفَّر بعد أي دخول ناجح.
  int pendingUnsyncedActions = 0;

  /// رسالة عربية تُعرض في شاشة الدخول بعد خروج قسري (§الإصلاح 1).
  String? forcedSignOutNotice;

  bool get isManager => role == sa.UserRole.manager;
  Currency get currency => Currency.of(salon?.currency);

  /// يحفظ بيانات الصالون والحساب القادمة مع الجلسة (دخول/تسجيل).
  Future<void> _adoptSession(sa.Session session) async {
    salon = SalonMeta.fromInfo(session.salon);
    salonTimezone = salon?.timezone ?? sa.defaultSalonTimezone;
    await services.prefs.setSalon(salon);
    final name = session.account?.name;
    if (name != null) {
      accountName = name;
      await services.prefs.setAccountName(name);
    }
  }

  Future<void> bootstrap() async {
    try {
      final s = await services.api.restoreSession();
      if (s != null && s.role != sa.UserRole.customer) {
        role = s.role;
        salon = s.salon.name != null
            ? SalonMeta.fromInfo(s.salon)
            : (services.prefs.salon ?? SalonMeta(code: s.salonCode));
        salonTimezone = salon?.timezone ?? sa.defaultSalonTimezone;
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
    sa.Session session;
    try {
      session = await services.api.loginStaff(
        salonCode: code,
        username: user,
        password: password,
        rememberMe: rememberMe,
      );
    } on sa.ApiError catch (e) {
      // ق: حساب أو صالون مُوقف — هذا هو المكان الوحيد الذي يصرّح فيه
      // السيرفر بذلك صراحة (docs/api.md)؛ إبطال الجلسات عن إيقاف يصل لاحقًا
      // بـ401 عامّ لا يميَّز عن إبطال جلسة عادي، فلا يُمسح التخزين هناك.
      if (e.isAccountSuspended) {
        await services.destroyLocalStore();
        pendingUnsyncedActions = 0;
        forcedSignOutNotice = null;
      }
      rethrow;
    }
    if (session.role == sa.UserRole.customer) {
      await services.api.logout();
      throw const sa.ApiError(
        code: 'NOT_STAFF',
        message: 'هذا التطبيق للطاقم فقط. استخدم تطبيق «صالوني» للزبائن.',
      );
    }
    await _adoptOwner('${session.salonCode}|$user');
    await services.prefs.rememberLogin(code, user);
    await _adoptSession(session);
    role = session.role;
    status = AuthStatus.signedIn;
    pendingUnsyncedActions = 0;
    forcedSignOutNotice = null;
    sessionKey++;
    notifyListeners();
  }

  /// يحدّث بيانات الصالون (مثل انتهاء «بانتظار التفعيل») من `GET /auth/session`.
  Future<void> refreshSessionInfo() async {
    try {
      final info = await services.api.getSessionInfo();
      salon = SalonMeta.fromInfo(info.salon);
      salonTimezone = salon?.timezone ?? sa.defaultSalonTimezone;
      await services.prefs.setSalon(salon);
      notifyListeners();
    } on sa.ApiError catch (_) {
      // دون اتصال: تبقى البيانات المعروفة.
    }
  }

  /// ق37: تسجيل صالون جديد — يعيد رمز الصالون. المالك يدخل كمدير مباشرة.
  Future<String> registerSalon({
    required Map<String, dynamic> salonData,
    required Map<String, dynamic> owner,
  }) async {
    final reg = await services.api.registerSalon(salon: salonData, owner: owner);
    final session = reg.session;
    await _adoptOwner('${session.salonCode}|${owner['username']}');
    await services.prefs.rememberLogin(session.salonCode, owner['username'].toString());
    await _adoptSession(session);
    salon = SalonMeta.fromInfo(reg.salon);
    salonTimezone = salon?.timezone ?? sa.defaultSalonTimezone;
    await services.prefs.setSalon(salon);
    role = session.role;
    return reg.salon.code;
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
      await services.destroyLocalStore();
      pendingUnsyncedActions = 0;
      forcedSignOutNotice = null;
    }
    await services.prefs.setStoreOwner(owner);
  }

  /// خروج اختياري: يُستدعى بعد مسح مستودع الطابور (انظر `signOut`).
  Future<void> logout() async {
    await services.api.logout();
    await services.prefs.setSalon(null);
    await services.prefs.setAccountName(null);
    await services.prefs.setStoreOwner(null);
    pendingUnsyncedActions = 0;
    forcedSignOutNotice = null;
    _clear();
  }

  /// انتهت الجلسة: تجديد رفضه السيرفر (401/403) — جلسة أُبطلت (نقل يدوي،
  /// كشف إعادة استخدام رمز، إعادة تعيين كلمة مرور)، أو حساب/صالون أُوقف
  /// (`ACCOUNT_SUSPENDED`/`SALON_SUSPENDED` يُلغي جلساته فيصل التجديد لاحقًا
  /// بـ401 عامّ لا يميَّز هنا عن أي إبطال آخر — docs/api.md، design.md §7).
  ///
  /// **لا تُمسح** قاعدة SQLCipher ولا صندوق الأحداث المعلّقة هنا: قد تكون
  /// جلسة أُبطلت فقط لا حسابًا مُوقفًا، فمسح صندوق لم يُزامن بعد يفقد عمل
  /// الحلاق. يُغلق مقبض القاعدة النشط فقط (يمنع فتح مقبض ثانٍ متزامن لاحقًا،
  /// وهو ما كان يسبب تلفًا محتملًا)، وتُعرض للحلاق رسالة بعدد المعلّق ليدخل
  /// من جديد. المسح الفعلي يحدث فقط عند: (أ) تأكيد الإيقاف صراحة عند محاولة
  /// الدخول التالية ([login])، أو (ب) دخول حساب مختلف على هذا الجهاز
  /// ([_adoptOwner]). بعد دخول **نفس** الحساب يُزامَن الصندوق المحفوظ تلقائيًا
  /// (المحرك يُرسله عند أول `refresh`).
  void _forcedSignOut() {
    if (status != AuthStatus.signedIn) return;
    unawaited(_handleForcedSignOut());
  }

  Future<void> _handleForcedSignOut() async {
    final pending = await _pendingOutboxCount();
    // يغلق مقبض القاعدة النشط (مقبض المستودع الحالي) قبل أي شيء آخر — لا
    // يُفتح مقبض جديد هنا إطلاقًا، فلا يوجد قط مقبضان مفتوحان على نفس الملف.
    await services.closeActiveHandle();
    try {
      await services.device.stopKeepAlive();
    } catch (_) {}
    pendingUnsyncedActions = pending;
    forcedSignOutNotice = pending > 0
        ? 'انقطعت الجلسة، لكن ${_arNum(pending)} لم تُزامن بعد وبقيت محفوظة على الجهاز. '
            'سجّل الدخول بنفس الحساب لإكمال المزامنة.'
        : 'انقطعت الجلسة. يرجى تسجيل الدخول من جديد.';
    _clear();
  }

  Future<int> _pendingOutboxCount() async {
    final h = services.activeHandle;
    if (h == null) return 0;
    try {
      return (await h.store.getOutbox()).length;
    } catch (_) {
      return 0;
    }
  }

  String _arNum(int n) => n == 1 ? 'إجراءً واحدًا' : (n == 2 ? 'إجراءين' : '$n إجراءات');

  void _clear() {
    role = null;
    salon = null;
    salonTimezone = sa.defaultSalonTimezone;
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
    openStore: services.openLocalStore,
    onHandleReleased: () => services.activeHandle = null,
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

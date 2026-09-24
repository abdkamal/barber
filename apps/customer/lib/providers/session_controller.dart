import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saloni_api/saloni_api.dart';

import '../models/salon_session.dart';
import '../services/api_client_factory.dart';
import '../services/customer_api.dart';
import '../services/multi_salon_store.dart';

enum SessionStatus { loading, needsSalon, pendingApproval, ready, error }

class SessionState {
  const SessionState({
    this.status = SessionStatus.loading,
    this.savedSalons = const [],
    this.activeCode,
    this.activeName,
    this.api,
    this.errorMessage,
  });

  final SessionStatus status;
  final List<SalonSession> savedSalons;
  final String? activeCode;
  final String? activeName;
  final CustomerApi? api;
  final String? errorMessage;

  SessionState copyWith({
    SessionStatus? status,
    List<SalonSession>? savedSalons,
    String? activeCode,
    String? activeName,
    CustomerApi? api,
    String? errorMessage,
    bool clearError = false,
  }) =>
      SessionState(
        status: status ?? this.status,
        savedSalons: savedSalons ?? this.savedSalons,
        activeCode: activeCode ?? this.activeCode,
        activeName: activeName ?? this.activeName,
        api: api ?? this.api,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

/// المتحكم المركزي بجلسة الزبون: الصالونات المحفوظة على الجهاز، الصالون
/// الفعّال، وعميل الواجهة البرمجية المرتبط به (ق7).
///
/// **ملاحظة صدق:** كشف حالة «بانتظار الاعتماد» يعتمد على أن يعيد السيرفر خطأ
/// برمز `ACCOUNT_PENDING` عند استدعاء نقاط الزبون المحمية لحساب لم يُعتمد
/// بعد؛ هذا الرمز غير موثّق حرفيًا في `docs/api.md` (أقرب ما وثّقه القسم هو
/// نص "حساب ينتظر الاعتماد" في التنبيهات §8). اعتُمد كأقرب قراءة آمنة
/// ومتّسقة مع تسمية بقية الأكواد (`SLOT_UNAVAILABLE`…)، ويجب تأكيدها مع فريق
/// السيرفر قبل الاعتماد النهائي.
class SessionController extends StateNotifier<SessionState> {
  SessionController(this._factory, this._store) : super(const SessionState()) {
    _bootstrap();
  }

  final ApiClientFactory _factory;
  final MultiSalonStore _store;

  Future<void> _bootstrap() async {
    final salons = await _store.loadAll();
    final activeCode = await _store.activeCode();
    if (activeCode == null || salons.every((s) => s.code != activeCode)) {
      state = state.copyWith(status: SessionStatus.needsSalon, savedSalons: salons);
      return;
    }
    await _activate(activeCode, salons);
  }

  Future<void> _activate(String code, List<SalonSession> salons) async {
    final saved = salons.firstWhere((s) => s.code == code);
    final client = _factory.forSalon(code, saved.name);
    await client.restoreSession();
    final api = RealCustomerApi(client);
    state = state.copyWith(
      status: SessionStatus.loading,
      savedSalons: salons,
      activeCode: code,
      activeName: saved.name,
      api: api,
    );
    await _confirmActiveAccount(api, code);
  }

  Future<void> _confirmActiveAccount(CustomerApi api, String code) async {
    try {
      await api.getCustomerToday();
      state = state.copyWith(status: SessionStatus.ready, clearError: true);
    } on ApiError catch (e) {
      if (e.code == 'ACCOUNT_PENDING') {
        state = state.copyWith(status: SessionStatus.pendingApproval, clearError: true);
      } else if (e.code == 'SIGNED_OUT') {
        await _store.clearActive();
        state = state.copyWith(status: SessionStatus.needsSalon, clearError: true);
      } else {
        state = state.copyWith(status: SessionStatus.error, errorMessage: e.message);
      }
    } catch (_) {
      state = state.copyWith(
        status: SessionStatus.error,
        errorMessage: 'تعذّر الاتصال بالسيرفر. تحقق من اتصالك وحاول مجددًا.',
      );
    }
  }

  /// عميل مؤقت بلا جلسة — لصفحة رمز الصالون و«حول الصالون» قبل الدخول.
  CustomerApi anonymousApi() => RealCustomerApi(_factory.anonymous());

  Future<void> registerAndActivate({
    required String salonCode,
    required String name,
    required String phone,
    required String password,
    required bool rememberMe,
  }) async {
    final client = _factory.forSalon(salonCode, name);
    final api = RealCustomerApi(client);
    final session = await api.registerCustomer(
      salonCode: salonCode,
      name: name,
      phone: phone,
      password: password,
      rememberMe: rememberMe,
    );
    await _afterAuth(salonCode: salonCode, name: name, session: session, api: api, rememberMe: rememberMe);
  }

  Future<void> loginAndActivate({
    required String salonCode,
    required String salonName,
    required String phone,
    required String password,
    required bool rememberMe,
  }) async {
    final client = _factory.forSalon(salonCode, salonName);
    final api = RealCustomerApi(client);
    final session = await api.loginCustomer(
      salonCode: salonCode,
      phone: phone,
      password: password,
      rememberMe: rememberMe,
    );
    await _afterAuth(
      salonCode: salonCode,
      name: salonName,
      session: session,
      api: api,
      rememberMe: rememberMe,
    );
  }

  Future<void> _afterAuth({
    required String salonCode,
    required String name,
    required Session session,
    required RealCustomerApi api,
    required bool rememberMe,
  }) async {
    await _store.upsert(
      SalonSession(code: salonCode, name: name, session: session),
      rememberMe: rememberMe,
    );
    await _store.setActiveCode(salonCode);
    final salons = await _store.loadAll();
    state = state.copyWith(
      status: SessionStatus.loading,
      savedSalons: salons,
      activeCode: salonCode,
      activeName: name,
      api: api,
    );
    await _confirmActiveAccount(api, salonCode);
  }

  Future<void> switchSalon(String code) async {
    final salons = await _store.loadAll();
    if (salons.every((s) => s.code != code)) return;
    await _store.setActiveCode(code);
    await _activate(code, salons);
  }

  Future<void> addAnotherSalon() async {
    await _store.clearActive();
    final salons = await _store.loadAll();
    state = state.copyWith(status: SessionStatus.needsSalon, savedSalons: salons);
  }

  Future<void> removeSalon(String code) async {
    await _store.remove(code);
    await _bootstrap();
  }

  Future<void> logoutActive() async {
    final api = state.api;
    if (api != null) {
      try {
        await api.logout();
      } catch (_) {}
    }
    if (state.activeCode != null) {
      await _store.remove(state.activeCode!);
    }
    await _bootstrap();
  }

  Future<void> retry() => _bootstrap();
}

final multiSalonStoreProvider = Provider<MultiSalonStore>((ref) => MultiSalonStore());

final apiClientFactoryProvider = Provider<ApiClientFactory>(
  (ref) => ApiClientFactory(ref.watch(multiSalonStoreProvider)),
);

final sessionControllerProvider = StateNotifierProvider<SessionController, SessionState>(
  (ref) => SessionController(
    ref.watch(apiClientFactoryProvider),
    ref.watch(multiSalonStoreProvider),
  ),
);

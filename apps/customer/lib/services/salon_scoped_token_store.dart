import 'package:saloni_api/saloni_api.dart';

import '../models/salon_session.dart';
import 'multi_salon_store.dart';

/// يقرأ/يكتب جلسة صالون واحد بعينه فوق [MultiSalonStore] — يسمح بأكثر من حساب
/// محفوظ في آنٍ واحد (ق7)، بينما [ApiClient] يتعامل مع جلسة واحدة فقط في كل
/// نسخة منه.
class SalonScopedTokenStore implements TokenStore {
  SalonScopedTokenStore({
    required this.salonCode,
    required this.salonName,
    required MultiSalonStore store,
  }) : _store = store; // ignore: prefer_initializing_formals — الاسم العام أوضح عند الاستدعاء.

  final String salonCode;
  final String salonName;
  final MultiSalonStore _store;

  @override
  Future<Session?> read() async {
    final saved = await _store.get(salonCode);
    return saved?.session;
  }

  @override
  Future<void> save(Session session, {required bool persist}) async {
    await _store.upsert(
      SalonSession(code: salonCode, name: salonName, session: session),
      rememberMe: persist,
    );
  }

  @override
  Future<void> clear() async {
    await _store.remove(salonCode);
  }
}

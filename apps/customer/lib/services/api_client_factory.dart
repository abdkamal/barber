import 'package:saloni_api/saloni_api.dart';

import '../config/env.dart';
import 'multi_salon_store.dart';
import 'salon_scoped_token_store.dart';

/// يبني نسخ [ApiClient] — واحدة لكل صالون فعّال (جلسة مستقلة، ق7)، وأخرى
/// بلا حساب لصفحات ما قبل الدخول («حول الصالون»، إدخال رمز الصالون).
class ApiClientFactory {
  ApiClientFactory(this.multiSalonStore);

  final MultiSalonStore multiSalonStore;

  ApiClient anonymous() => ApiClient(
        baseUrl: Env.apiBaseUrl,
        tokenStore: InMemoryTokenStore(),
      );

  ApiClient forSalon(String code, String name) => ApiClient(
        baseUrl: Env.apiBaseUrl,
        tokenStore: SalonScopedTokenStore(
          salonCode: code,
          salonName: name,
          store: multiSalonStore,
        ),
      );
}

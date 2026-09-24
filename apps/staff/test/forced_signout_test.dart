import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_staff/core/platform/storage.dart';
import 'package:saloni_staff/state/app_services.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

void main() {
  testWidgets(
    'جلسة أُبطلت (401/403 عند التجديد، مثل ACCOUNT_SUSPENDED): تُمسح قاعدة SQLCipher المحلية فورًا (design.md §6.1)',
    (tester) async {
      final server = FakeServer(role: 'barber');
      server.booking(id: 'q1', name: 'فهد');
      final h = await pumpStaffApp(tester, server);

      // الطابور محفوظ محليًا بعد أول مزامنة ناجحة.
      final storage = h.services.storage as InMemoryStoragePlatform;
      expect((await storage.shared.getQueue()), isNotEmpty);
      expect(h.auth.status, AuthStatus.signedIn);

      // السيرفر يوقف الحساب/يبطل الجلسة: كل الطلبات ثم التجديد يعيدان 401.
      server.sessionRevoked = true;

      // يطلق دورة مزامنة جديدة (نبضة/سحب) فتصطدم بـ401 ثم يفشل التجديد.
      await h.container.read(barberRepoProvider).refresh();
      await settle(tester);

      expect(h.auth.status, AuthStatus.signedOut, reason: 'خرج المستخدم قسرًا');
      expect(await storage.shared.getQueue(), isEmpty, reason: 'مُسح الطابور المحلي فورًا لا عند خروج صريح فقط');

      await teardownApp(tester, h);
    },
  );
}

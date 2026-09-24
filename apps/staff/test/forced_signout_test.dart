import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_api/saloni_api.dart' as sa;
import 'package:saloni_staff/core/platform/storage.dart';
import 'package:saloni_staff/state/app_services.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

void main() {
  testWidgets(
    'جلسة أُبطلت (401/403 عند التجديد — نقل يدوي/كشف إعادة استخدام/إعادة '
    'تعيين كلمة مرور): يبقى الصندوق والمستودع المحليان، ثم يُزامنان تلقائيًا '
    'بعد دخول نفس الحساب من جديد',
    (tester) async {
      final server = FakeServer(role: 'barber');
      server.booking(id: 'q1', name: 'فهد');
      final h = await pumpStaffApp(tester, server, signedIn: false);

      // دخول أول يُثبّت «صاحب البيانات المحلية» (رمز الصالون|اسم المستخدم).
      await h.auth.login(
        salonCode: 'RAHA-27',
        username: 'khaled',
        password: 'x',
        rememberMe: true,
      );
      await settle(tester);
      expect(h.auth.status, AuthStatus.signedIn);

      final storage = h.services.storage as InMemoryStoragePlatform;
      expect(await storage.shared.getQueue(), isNotEmpty);

      // السيرفر يبطل الجلسة (نقل يدوي/كشف إعادة استخدام رمز/إعادة تعيين
      // كلمة مرور — كلها 401 عامّ لا تفصح عن السبب، docs/api.md). يسجّل
      // الحلاق إجراءً محليًا أولًا فيبقى معلّقًا في الصندوق.
      server.sessionRevoked = true;
      await h.container.read(barberRepoProvider).startBreak(sa.BreakKind.rest);
      await settle(tester);

      expect(h.auth.status, AuthStatus.signedOut, reason: 'خرج المستخدم قسرًا');
      expect(h.auth.forcedSignOutNotice, isNotNull);
      expect(h.auth.pendingUnsyncedActions, greaterThan(0));

      // **لا يُمسح** الطابور المحلي ولا الصندوق المعلّق — هذا هو الإصلاح.
      expect(await storage.shared.getQueue(), isNotEmpty,
          reason: 'الطابور المحلي يبقى محفوظًا بعد إبطال جلسة (لا إيقاف حساب)');
      expect(await storage.shared.getOutbox(), isNotEmpty,
          reason: 'الإجراء المعلّق يبقى في الصندوق ليُزامَن لاحقًا');

      // يعود الاتصال ويسجّل الحلاق دخوله بنفس الحساب من جديد.
      server.sessionRevoked = false;
      await h.auth.login(
        salonCode: 'RAHA-27',
        username: 'khaled',
        password: 'x',
        rememberMe: true,
      );
      await settle(tester);

      expect(h.auth.status, AuthStatus.signedIn);
      expect(h.auth.forcedSignOutNotice, isNull);
      expect(h.auth.pendingUnsyncedActions, 0);
      // الصندوق المحفوظ سابقًا زُومن تلقائيًا (المحرك يرسله عند أول تحديث).
      expect(server.eventTypes, contains('break_started'),
          reason: 'الصندoق المحتفظ به بعد إعادة الدخول بنفس الحساب يُزامن تلقائيًا');

      await teardownApp(tester, h);
    },
  );

  testWidgets(
    'حساب موقوف صراحة (403 ACCOUNT_SUSPENDED عند الدخول): يُمسح التخزين '
    'المحلي فورًا',
    (tester) async {
      final server = FakeServer(role: 'barber');
      server.booking(id: 'q1', name: 'فهد');
      final h = await pumpStaffApp(tester, server, signedIn: false);

      await h.auth.login(salonCode: 'RAHA-27', username: 'khaled', password: 'x', rememberMe: true);
      await settle(tester);
      final storage = h.services.storage as InMemoryStoragePlatform;
      expect(await storage.shared.getQueue(), isNotEmpty);

      // خروج قسري (جلسة أُبطلت — السبب غير معروف للجهاز بعد) يترك البيانات.
      server.sessionRevoked = true;
      await h.container.read(barberRepoProvider).refresh();
      await settle(tester);
      expect(h.auth.status, AuthStatus.signedOut);
      expect(await storage.shared.getQueue(), isNotEmpty);

      // محاولة الدخول من جديد تكشف الآن أن الحساب مُوقف صراحة.
      server.sessionRevoked = false;
      server.loginSuspended = true;
      await expectLater(
        h.auth.login(
            salonCode: 'RAHA-27', username: 'khaled', password: 'x', rememberMe: true),
        throwsA(isA<sa.ApiError>().having((e) => e.code, 'code', 'ACCOUNT_SUSPENDED')),
      );
      await settle(tester);

      expect(await storage.shared.getQueue(), isEmpty,
          reason: 'تأكّد الإيقاف صراحة عند الدخول — يُمسح التخزين المحلي الآن');
      expect(await storage.shared.getOutbox(), isEmpty);

      await teardownApp(tester, h);
    },
  );

  testWidgets(
    'ق40: دخول حساب مختلف على جهاز يحمل إجراءات لم تُرفع لصاحبه: يُحجز '
    'الجهاز (لا مسح ولا دخول)، وبصندوق فارغ يُمسح ويدخل الحساب الجديد كما كان',
    (tester) async {
      final server = FakeServer(role: 'barber');
      server.booking(id: 'q1', name: 'فهد');
      final h = await pumpStaffApp(tester, server, signedIn: false);

      await h.auth.login(salonCode: 'RAHA-27', username: 'khaled', password: 'x', rememberMe: true);
      await settle(tester);
      final storage = h.services.storage as InMemoryStoragePlatform;
      expect(await storage.shared.getQueue(), isNotEmpty);

      // إجراء معلّق لخالد قبل إبطال جلسته.
      server.sessionRevoked = true;
      await h.container.read(barberRepoProvider).startBreak(sa.BreakKind.rest);
      await settle(tester);
      expect(h.auth.status, AuthStatus.signedOut);
      expect(await storage.shared.getOutbox(), isNotEmpty, reason: 'لم يُمسح بعد — السبب غير معروف');

      // حلاق آخر (اسم مستخدم مختلف) يحاول الدخول على هذا الجهاز.
      server.sessionRevoked = false;
      final loginsBefore = server.requests.where((r) => r == 'POST /auth/staff/login').length;
      await expectLater(
        h.auth.login(salonCode: 'RAHA-27', username: 'sami', password: 'y', rememberMe: true),
        throwsA(isA<sa.ApiError>().having((e) => e.code, 'code', 'DEVICE_HELD')),
      );
      await settle(tester);

      expect(h.auth.status, AuthStatus.signedOut, reason: 'لا يدخل حساب آخر فوق إجراءات لم تُرفع');
      expect(h.auth.hold?.reason, HoldReason.otherAccount);
      expect(h.auth.hold?.username, 'khaled');
      expect(server.requests.where((r) => r == 'POST /auth/staff/login').length, loginsBefore,
          reason: 'حُجز الجهاز قبل إرسال بيانات دخول سامي');
      expect(await storage.shared.getOutbox(), isNotEmpty, reason: 'الصندوق باقٍ مشفّرًا');
      expect(server.eventTypes, isNot(contains('break_started')),
          reason: 'الإجراء المعلّق لخالد لم يُزامَن أبدًا مع حساب سامي');
      expect(find.text('إجراءات حساب آخر'), findsOneWidget);

      // صاحب الجهاز يمسح دون رفع (بتأكيد) ← يدخل سامي على جهاز نظيف.
      await h.auth.discardHeld();
      await settle(tester);
      expect(await storage.shared.getOutbox(), isEmpty);
      await h.auth.login(salonCode: 'RAHA-27', username: 'sami', password: 'y', rememberMe: true);
      await settle(tester);
      expect(h.auth.status, AuthStatus.signedIn);
      expect(server.eventTypes, isNot(contains('break_started')));

      await teardownApp(tester, h);
    },
  );
}

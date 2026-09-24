import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saloni_api/saloni_api.dart' as sa;
import 'package:saloni_staff/core/platform/storage.dart';
import 'package:saloni_staff/state/app_services.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

/// ق40: إجراءات حلاق أُوقف حسابه وهو دون اتصال — «سلّم الجهاز للمدير».
Future<void> _pause(WidgetTester tester) =>
    tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));

String _path(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(Scaffold).first)).routeInformationProvider.value.uri.path;

/// خالد يسجّل دخوله، ثم ينقطع ويبدأ خدمة وينهيها دون اتصال؛ يُعاد [cut] بين
/// الحدثين (وقت الإيقاف المحاكى)، ثم تُبطل جلسته فيخرج قسرًا والصندوق ممتلئ.
Future<DateTime> _barberWithPendingActions(WidgetTester tester, Harness h) async {
  final server = h.server;
  await h.auth.login(salonCode: 'RAHA-27', username: 'khaled', password: 'x', rememberMe: true);
  await settle(tester);
  final repo = h.container.read(barberRepoProvider);
  server.online = false;
  await repo.startService('q1');
  await settle(tester);
  await _pause(tester);
  final cut = DateTime.now().toUtc();
  await _pause(tester);
  await repo.finishService('q1');
  await settle(tester);
  server.online = true;
  server.sessionRevoked = true;
  await repo.refresh();
  await settle(tester);
  expect(h.auth.status, AuthStatus.signedOut);
  server.sessionRevoked = false;
  return cut;
}

void main() {
  testWidgets(
    'حساب موقوف وفي الصندوق إجراءات: لا مسح؛ شاشة «سلّم الجهاز للمدير»؛ المدير '
    'يرفعها فيُقبل ما قبل الإيقاف ويُرفض ما بعده، ثم يُمسح الجهاز وتُنهى جلسة المدير',
    (tester) async {
      final server = FakeServer(role: 'barber');
      server.booking(id: 'q1', name: 'فهد');
      server.managerStaff = [
        {'id': 'barber-1', 'name': 'خالد الحربي', 'username': 'khaled', 'role': 'barber', 'active': false},
        {'id': 'mgr-1', 'name': 'المدير', 'username': 'boss', 'role': 'manager', 'active': true},
      ];
      server.loginRoles['boss'] = 'manager';
      server.loginRoles['ali'] = 'barber';
      final h = await pumpStaffApp(tester, server, signedIn: false);
      final storage = h.services.storage as InMemoryStoragePlatform;

      final cut = await _barberWithPendingActions(tester, h);
      final pending = (await storage.shared.getOutbox()).length;
      expect(pending, 2);
      server.suspendedAt = cut;
      server.suspendedUsers.add('khaled');

      // محاولة الدخول تكشف الإيقاف — لكن الصندوق لا يُمسح.
      await expectLater(
        h.auth.login(salonCode: 'RAHA-27', username: 'khaled', password: 'x', rememberMe: true),
        throwsA(isA<sa.ApiError>().having((e) => e.code, 'code', 'ACCOUNT_SUSPENDED')),
      );
      await settle(tester);
      expect(await storage.shared.getOutbox(), hasLength(2), reason: 'ق40: لا مسح قبل رفع المدير');
      expect(h.auth.hold?.reason, HoldReason.accountSuspended);
      expect(_path(tester), '/hold');
      expect(find.text('الحساب موقوف'), findsOneWidget);
      expect(find.textContaining('سلّم الجهاز للمدير لرفعها'), findsOneWidget);
      expect(find.text('إجراءان لم تُرفع بعد'), findsOneWidget);

      // حساب حلاق (لا مدير) على شاشة الحجز: يُرفض ولا يُرفع شيء.
      await tester.enterText(find.byType(TextField).at(0), 'ali');
      await tester.enterText(find.byType(TextField).at(1), 'pw');
      await tester.ensureVisible(find.text('دخول المدير ورفع الإجراءات'));
      await tester.tap(find.text('دخول المدير ورفع الإجراءات'));
      await settle(tester);
      expect(find.textContaining('ليس حساب مدير'), findsOneWidget);
      expect(server.recoveredUploads, isEmpty);
      expect(await storage.shared.getOutbox(), hasLength(2));

      // المدير يدخل ويرفع.
      await tester.enterText(find.byType(TextField).at(0), 'boss');
      await tester.enterText(find.byType(TextField).at(1), 'manager-pw');
      await tester.ensureVisible(find.text('دخول المدير ورفع الإجراءات'));
      await tester.tap(find.text('دخول المدير ورفع الإجراءات'));
      await settle(tester);

      expect(server.recoveredUploads.map((e) => e['type']), ['service_started', 'service_finished']);
      expect(server.recoveredUploads.every((e) => e['staffId'] == 'barber-1'), isTrue);
      expect(server.requests, contains('POST /manager/staff/barber-1/recover-events'));
      expect(find.text('اكتمل الرفع'), findsOneWidget);
      expect(find.text('قُبلت'), findsOneWidget);
      expect(find.text('رُفضت لوقوعها بعد الإيقاف'), findsOneWidget);
      expect(h.auth.recoveryReport?.summary.applied, 1);
      expect(h.auth.recoveryReport?.summary.rejectedAfterSuspension, 1);
      // مُسح التخزين، ولا تبقى جلسة المدير على جهاز الحلاق.
      expect(await storage.shared.getOutbox(), isEmpty);
      expect(await storage.shared.getQueue(), isEmpty);
      expect(h.services.prefs.storeOwner, isNull);
      expect(server.requests.last, 'POST /auth/logout');
      expect(await h.services.storage.createTokenStore().read(), isNull);
      expect(h.auth.status, AuthStatus.signedOut);

      await tester.ensureVisible(find.text('تم'));
      await tester.tap(find.text('تم'));
      await settle(tester);
      expect(h.auth.hold, isNull);
      expect(_path(tester), '/login');

      await teardownApp(tester, h);
    },
  );

  testWidgets(
    'الحساب غير موقوف (409) يبقي الصندوق؛ «مسح دون رفع» يطلب تأكيدًا ثم يمسح',
    (tester) async {
      final server = FakeServer(role: 'barber');
      server.booking(id: 'q1', name: 'فهد');
      server.managerStaff = [
        {'id': 'barber-1', 'name': 'خالد الحربي', 'username': 'khaled', 'role': 'barber', 'active': true},
      ];
      server.loginRoles['boss'] = 'manager';
      final h = await pumpStaffApp(tester, server, signedIn: false);
      final storage = h.services.storage as InMemoryStoragePlatform;
      await _barberWithPendingActions(tester, h);

      // حلاق آخر يحاول الدخول ← الجهاز محجوز.
      await expectLater(
        h.auth.login(salonCode: 'RAHA-27', username: 'sami', password: 'y', rememberMe: true),
        throwsA(isA<sa.ApiError>()),
      );
      await settle(tester);
      expect(_path(tester), '/hold');
      expect(find.text('إجراءات حساب آخر'), findsOneWidget);

      // المدير يحاول الرفع، لكن خالد غير موقوف: رسالة واضحة، والصندوق باقٍ.
      await tester.enterText(find.byType(TextField).at(0), 'boss');
      await tester.enterText(find.byType(TextField).at(1), 'pw');
      await tester.ensureVisible(find.text('دخول المدير ورفع الإجراءات'));
      await tester.tap(find.text('دخول المدير ورفع الإجراءات'));
      await settle(tester);
      expect(find.textContaining('غير موقوف'), findsOneWidget);
      expect(await storage.shared.getOutbox(), hasLength(2));
      expect(server.requests.last, 'POST /auth/logout', reason: 'جلسة المدير تُنهى حتى عند الفشل');

      // «مسح دون رفع» ← تأكيد ← «تراجع» لا يمسح.
      await tester.ensureVisible(find.text('مسح دون رفع'));
      await tester.tap(find.text('مسح دون رفع'));
      await settle(tester);
      expect(find.text('مسح دون رفع؟'), findsOneWidget);
      await tester.tap(find.text('تراجع'));
      await settle(tester);
      expect(await storage.shared.getOutbox(), hasLength(2));

      await tester.ensureVisible(find.text('مسح دون رفع'));
      await tester.tap(find.text('مسح دون رفع'));
      await settle(tester);
      await tester.tap(find.text('مسح نهائيًا'));
      await settle(tester);
      expect(await storage.shared.getOutbox(), isEmpty);
      expect(h.auth.hold, isNull);
      expect(_path(tester), '/login');
      expect(server.recoveredUploads, isEmpty);

      await teardownApp(tester, h);
    },
  );

  testWidgets('«رجوع لتسجيل الدخول» يبقي البيانات، ودخول صاحبها بعد إعادة تفعيله يزامنها', (tester) async {
    final server = FakeServer(role: 'barber');
    server.booking(id: 'q1', name: 'فهد');
    final h = await pumpStaffApp(tester, server, signedIn: false);
    final storage = h.services.storage as InMemoryStoragePlatform;
    await _barberWithPendingActions(tester, h);
    server.suspendedUsers.add('khaled');
    await expectLater(
      h.auth.login(salonCode: 'RAHA-27', username: 'khaled', password: 'x', rememberMe: true),
      throwsA(isA<sa.ApiError>()),
    );
    await settle(tester);
    await tester.ensureVisible(find.text('رجوع لتسجيل الدخول'));
    await tester.tap(find.text('رجوع لتسجيل الدخول'));
    await settle(tester);
    expect(_path(tester), '/login');
    expect(await storage.shared.getOutbox(), hasLength(2));

    // أُعيد تفعيل الحساب: يدخل خالد فيُزامَن صندوقه بالطريق العادي.
    server.suspendedUsers.clear();
    await h.auth.login(salonCode: 'RAHA-27', username: 'khaled', password: 'x', rememberMe: true);
    await settle(tester);
    expect(h.auth.status, AuthStatus.signedIn);
    expect(server.eventTypes, containsAll(['service_started', 'service_finished']));
    await teardownApp(tester, h);
  });

  testWidgets('المدير: «إجراءات مستردة للمراجعة» تعرض العناصر وتعلّمها «تمت المراجعة»', (tester) async {
    final server = FakeServer(role: 'manager');
    server.recoveredItems = [
      {
        'id': 'item-1',
        'staffId': 'barber-1',
        'staffName': 'خالد الحربي',
        'eventId': 'evt-1',
        'type': 'payment_confirmed',
        'bookingId': 'q1',
        'customerName': 'فهد',
        'occurredAt': DateTime.now().toUtc().subtract(const Duration(hours: 2)).toIso8601String(),
        'approximate': true,
        'suspendedAt': DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String(),
        'reason': null,
        'recoveredBy': {'id': 'mgr-1', 'name': 'المدير'},
        'recoveredAt': DateTime.now().toUtc().toIso8601String(),
        'reviewedAt': null,
        'reviewedBy': null,
      },
    ];
    final h = await pumpStaffApp(tester, server);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/m/recovered');
    await settle(tester);
    expect(find.text('إجراءات مستردة للمراجعة'), findsOneWidget);
    expect(find.text('تأكيد دفع — فهد'), findsOneWidget);
    expect(find.text('توقيت تقريبي'), findsOneWidget);
    expect(find.textContaining('رفعه المدير'), findsOneWidget);
    await tester.tap(find.text('تمت المراجعة'));
    await settle(tester);
    expect(server.acknowledged, ['item-1']);
    expect(find.text('لا إجراءات بانتظار المراجعة'), findsOneWidget);
    await teardownApp(tester, h);
  });
}

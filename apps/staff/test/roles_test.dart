import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

GoRouter _router(WidgetTester tester) => GoRouter.of(tester.element(find.byType(Scaffold).first));

void main() {
  testWidgets('الحلاق: مسارات المدير مخفية ومحوّلة إلى طابوري', (tester) async {
    final server = FakeServer(role: 'barber');
    final h = await pumpStaffApp(tester, server);

    expect(find.text('الطوابير'), findsNothing);
    expect(find.text('التقارير'), findsNothing);

    for (final path in ['/m/queues', '/m/reports', '/m/settings', '/m/staff', '/m/customers']) {
      _router(tester).go(path);
      await settle(tester);
      expect(_router(tester).routeInformationProvider.value.uri.path, '/b/queue', reason: path);
      expect(server.requests.where((r) => r.contains('/manager/')), isEmpty, reason: path);
    }

    _router(tester).go('/b/more');
    await settle(tester);
    expect(find.text('لوحة المدير'), findsNothing);
    await teardownApp(tester, h);
  });

  testWidgets('المدير: يبدأ بالطوابير ويرى التقارير', (tester) async {
    final server = FakeServer(role: 'manager')
      ..managerQueues = [
        {
          'barberId': 'b1',
          'barberName': 'خالد',
          'dayState': 'connected',
          'queue': [
            {'id': 'q1', 'customerName': 'فهد', 'status': 'waiting', 'services': [{'name': 'حلاقة شعر'}]},
          ],
        },
        {'barberId': 'b2', 'barberName': 'سعد', 'dayState': 'absent_today', 'queue': []},
      ];
    final h = await pumpStaffApp(tester, server);

    expect(find.text('الطوابير'), findsWidgets);
    expect(find.text('خالد'), findsOneWidget);
    expect(find.text('غائب اليوم'), findsOneWidget);

    // النقل اليدوي (ق25).
    await tester.tap(find.byKey(const Key('transfer-q1')));
    await settle(tester);
    expect(find.text('نقل حجز فهد'), findsOneWidget);
    await tester.tap(find.text('نقل الحجز'));
    await settle(tester);
    expect(server.requests.where((r) => r.contains('/transfer')), isEmpty,
        reason: 'لا نقل قبل اختيار حلاق متاح');
    await tester.tap(find.byType(Scaffold).first, warnIfMissed: false);
    await settle(tester);

    _router(tester).go('/m/reports');
    await settle(tester);
    expect(find.text('الإيراد المؤكد'), findsOneWidget);
    expect(find.text('1,240'), findsOneWidget);
    expect(find.text('حسب الحلاق'), findsOneWidget);
    await teardownApp(tester, h);
  });

  testWidgets('الدخول: رمز الصالون + اسم المستخدم + كلمة المرور ثم طابوري', (tester) async {
    final server = FakeServer(role: 'barber');
    final h = await pumpStaffApp(tester, server, signedIn: false);

    expect(find.text('دخول'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'raha-27');
    await tester.enterText(find.byType(TextField).at(1), 'khaled');
    await tester.enterText(find.byType(TextField).at(2), 'very-secret-pass');
    await tester.tap(find.text('دخول'));
    await settle(tester, 10);

    expect(server.requests, contains('POST /auth/staff/login'));
    expect(find.text('طابوري'), findsWidgets);
    expect(h.auth.salon?.name, 'صالون الراحة');
    expect(h.auth.accountName, 'خالد الحربي');
    await teardownApp(tester, h);
  });

  testWidgets('الخروج يمسح الطابور المحلي ويعيد لشاشة الدخول', (tester) async {
    final server = FakeServer()..booking(id: 'b1', name: 'فهد القحطاني', status: 'called');
    final h = await pumpStaffApp(tester, server);
    final store = (await h.services.storage.openLocalStore()).store;
    expect(await store.getQueue(), isNotEmpty);
    _router(tester).go('/b/more');
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('logout')));
    await tester.tap(find.byKey(const Key('logout')));
    await settle(tester);
    await tester.tap(find.text('خروج'));
    await settle(tester, 10);
    expect(find.text('دخول'), findsOneWidget);
    expect(server.requests, contains('POST /auth/logout'));
    expect(await store.getQueue(), isEmpty);
    expect(await store.getOutbox(), isEmpty);
    expect(await h.services.api.tokenStore.read(), isNull);
    await teardownApp(tester, h);
  });
}

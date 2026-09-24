import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

void main() {
  testWidgets('تسجيل صالون جديد (ق37): 4 خطوات ← بانتظار التفعيل ← ملف الصالون', (tester) async {
    final server = FakeServer();
    final h = await pumpStaffApp(tester, server, signedIn: false);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/signup');
    await settle(tester);

    expect(find.textContaining('الخطوة 1 من 4'), findsOneWidget);
    // التحقق: كلمة مرور قصيرة مرفوضة.
    await tester.enterText(find.byType(TextField).at(0), 'سالم');
    await tester.enterText(find.byType(TextField).at(1), 'salem');
    await tester.enterText(find.byType(TextField).at(2), 'short');
    await tester.enterText(find.byType(TextField).at(3), 'short');
    await tester.tap(find.text('التالي'));
    await tester.pump();
    expect(find.text('كلمة المرور 10 أحرف على الأقل'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(2), 'long-enough-pass');
    await tester.enterText(find.byType(TextField).at(3), 'long-enough-pass');
    await tester.tap(find.text('التالي'));
    await tester.pump();
    expect(find.textContaining('الخطوة 2 من 4'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'صالون جديد');
    await tester.tap(find.text('التالي'));
    await tester.pump();
    expect(find.textContaining('الخطوة 3 من 4'), findsOneWidget);
    await tester.tap(find.text('التالي'));
    await tester.pump();
    expect(find.textContaining('الخطوة 4 من 4'), findsOneWidget);

    await tester.tap(find.text('إضافة خدمة'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(0), 'حلاقة شعر');
    await tester.enterText(find.byType(TextField).at(2), '40');
    await tester.tap(find.text('إضافة'));
    await settle(tester);
    await tester.tap(find.text('إرسال للتفعيل'));
    await settle(tester, 12);

    expect(find.text('صالونك بانتظار التفعيل'), findsOneWidget);
    expect(find.text('NEW-42'), findsOneWidget);
    expect(server.registered?['owner']?['username'], 'salem');
    expect(server.registered?['salon']?['currency'], 'SAR');
    expect(server.schedulesPut, hasLength(7));
    expect(server.schedulesPut.first['staffId'], isNull);
    expect(server.servicesCreated.single, {'name': 'حلاقة شعر', 'durationMinutes': 30, 'price': 4000});

    await tester.tap(find.text('أكمل ملف الصالون'));
    await settle(tester);
    expect(find.text('ملف الصالون'), findsOneWidget);
    expect(find.text('صالونك بانتظار التفعيل'), findsOneWidget);
    await teardownApp(tester, h);
  });
}

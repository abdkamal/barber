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

  testWidgets('ملاحظات التجربة: الشيكل ₪ بلا علم، بلد الصالون، وساعات العمل تُعرض كما اختيرت', (tester) async {
    final server = FakeServer();
    // شاشة طويلة لتظهر قائمتا العملة والبلد كاملتين (اللمس لا يمر عبر الشريط السفلي).
    final h = await pumpStaffApp(tester, server, signedIn: false, height: 2000);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/signup');
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(0), 'سالم');
    await tester.enterText(find.byType(TextField).at(1), 'salem');
    await tester.enterText(find.byType(TextField).at(2), 'long-enough-pass');
    await tester.enterText(find.byType(TextField).at(3), 'long-enough-pass');
    await tester.tap(find.text('التالي'));
    await tester.pump();

    // الشيكل: رمزه ₪ علامته البصرية، ولا أعلام دول في القائمة.
    final ils = find.byKey(const Key('currency-ILS'));
    expect(find.descendant(of: ils, matching: find.text('₪')), findsOneWidget);
    expect(find.descendant(of: ils, matching: find.text('شيكل')), findsOneWidget);
    final allText = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').join();
    expect(allText.runes.any((r) => r >= 0x1F1E6 && r <= 0x1F1FF), isFalse, reason: 'لا أعلام');
    await tester.tap(ils);
    await tester.pump();
    expect(
        tester.widget<Semantics>(find.descendant(of: ils, matching: find.byType(Semantics)).first).properties.selected,
        isTrue);
    // ⓘ العملة يفتح الشرح.
    final currencyHelp = find.bySemanticsLabel('شرح: العملة');
    await tester.tap(currencyHelp);
    await settle(tester);
    expect(find.byKey(const Key('saloni-help-sheet')), findsOneWidget);
    await tester.tap(find.text('فهمت'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(0), 'صالون القدس');
    await tester.tap(find.text('التالي'));
    await tester.pump();

    // الخطوة 3: الافتتاح الافتراضي 10:00 يُعرض «10:00 ص» (لا تحويل بتوقيت الجهاز).
    expect(find.text('10:00 ص'), findsWidgets);
    expect(find.text('11:00 م'), findsWidgets);
    await tester.tap(find.text('التالي'));
    await tester.pump();
    await tester.tap(find.text('إضافة خدمة'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(0), 'حلاقة');
    await tester.enterText(find.byType(TextField).at(2), '40');
    expect(find.textContaining('₪'), findsWidgets);
    await tester.tap(find.text('إضافة'));
    await settle(tester);
    expect(find.textContaining('40'), findsWidgets);
    await tester.tap(find.text('إرسال للتفعيل'));
    await settle(tester, 12);

    expect(server.registered?['salon']?['currency'], 'ILS');
    expect(server.registered?['salon']?['timezone'], 'Asia/Hebron');
    expect(server.schedulesPut.first['opensAt'], '10:00');
    expect(server.servicesCreated.single['price'], 4000);
    await teardownApp(tester, h);
  });
}

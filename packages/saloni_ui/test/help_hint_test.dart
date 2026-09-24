import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_ui/saloni_ui.dart';

Widget _app(Widget child, {bool dark = true}) => MaterialApp(
      theme: dark ? SaloniTheme.dark() : SaloniTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: SingleChildScrollView(child: SizedBox(width: 360, child: child))),
      ),
    );

const _help = SaloniHelp(
  title: 'مدة حجز العرض',
  body: 'إذا لم تتوفر الساعة التي طلبها الزبون نعرض عليه أقرب وقت متاح ونحجزه له هذه المدة.',
  example: 'دقيقتان: إن لم يقبل خلالهما يعود الوقت متاحًا للجميع.',
  summary: 'كم يبقى الوقت المعروض محجوزًا للزبون.',
);

void main() {
  testWidgets('SaloniHelpHint يفتح ورقة الشرح بالعنوان والشرح والمثال ثم تُغلق بـ«فهمت»', (tester) async {
    await tester.pumpWidget(_app(const Center(child: SaloniHelpHint(_help))));
    expect(find.bySemanticsLabel('شرح: مدة حجز العرض'), findsOneWidget);
    await tester.tap(find.byType(SaloniHelpHint));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('saloni-help-sheet')), findsOneWidget);
    expect(find.text('مدة حجز العرض'), findsOneWidget);
    expect(find.textContaining('أقرب وقت متاح'), findsOneWidget);
    expect(find.textContaining('دقيقتان', findRichText: true), findsOneWidget);
    await tester.tap(find.text('فهمت'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('saloni-help-sheet')), findsNothing);
  });

  testWidgets('مساحة اللمس 40×40 (و32 بالوضع المضغوط)', (tester) async {
    await tester.pumpWidget(_app(const Row(children: [
      SaloniHelpHint(_help, key: Key('a')),
      SaloniHelpHint(_help, key: Key('b'), compact: true),
    ])));
    expect(tester.getSize(find.byKey(const Key('a'))), const Size(40, 40));
    expect(tester.getSize(find.byKey(const Key('b'))), const Size(32, 32));
  });

  testWidgets('SaloniTextField: ⓘ بجانب العنوان وسطر مساعد من الملخص', (tester) async {
    await tester.pumpWidget(_app(const SaloniTextField(label: 'مدة حجز العرض', help: _help)));
    expect(find.byType(SaloniHelpHint), findsOneWidget);
    expect(find.text('كم يبقى الوقت المعروض محجوزًا للزبون.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SaloniTextField: hint الصريح يتقدم على الملخص، وبلا help لا أيقونة', (tester) async {
    await tester.pumpWidget(_app(const Column(children: [
      SaloniTextField(label: 'أ', help: _help, hint: 'سطر صريح'),
      SaloniTextField(label: 'ب'),
    ])));
    expect(find.byType(SaloniHelpHint), findsOneWidget);
    expect(find.text('سطر صريح'), findsOneWidget);
    expect(find.text('كم يبقى الوقت المعروض محجوزًا للزبون.'), findsNothing);
  });

  testWidgets('SettingSwitch مع شرح: العنوان الطويل لا يتجاوز العرض، والتبديل يعمل', (tester) async {
    var v = false;
    await tester.pumpWidget(_app(SettingSwitch(
      label: 'اشتراط اعتماد الحسابات قبل أن يتمكن الزبون الجديد من الحجز',
      description: 'لا يحجز الزبون الجديد حتى تعتمد حسابه',
      help: _help,
      onChanged: (x) => v = x,
    ), dark: false));
    expect(tester.takeException(), isNull);
    expect(find.byType(SaloniHelpHint), findsOneWidget);
    await tester.tap(find.byType(GestureDetector).last);
    await tester.pump();
    expect(v, isTrue);
    await tester.tap(find.byType(SaloniHelpHint));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('saloni-help-sheet')), findsOneWidget);
  });
}

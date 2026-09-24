import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_staff/core/format.dart';

/// ق41: الأرقام غربية 0–9 دائمًا — حتى في عناصر Material المترجمة للعربية
/// (منتقي الوقت، التاريخ) تحت لغة التطبيق `ar`.
void main() {
  testWidgets('لغة ar في Material تعرض الساعات والتواريخ بأرقام غربية', (tester) async {
    useWesternDigitsEverywhere(); // كما في main()
    late MaterialLocalizations l;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(builder: (ctx) {
        l = MaterialLocalizations.of(ctx);
        return const SizedBox();
      }),
    ));
    final eastern = RegExp('[٠-٩۰-۹]');
    const t = TimeOfDay(hour: 9, minute: 5);
    expect(l.formatHour(t), '9');
    expect(l.formatMinute(t), '05');
    expect(l.formatTimeOfDay(t).contains(eastern), isFalse);
    expect(l.formatCompactDate(DateTime(2026, 9, 24)).contains(eastern), isFalse);
    expect(l.formatDecimal(1234), isNot(contains(eastern)));
  });
}

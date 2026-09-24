import 'package:customer/screens/about_salon_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_customer_api.dart';
import 'support/pump_app.dart';

void main() {
  testWidgets('يعرض حول الصالون قبل الدخول ويتيح المتابعة للتسجيل', (tester) async {
    final api = FakeCustomerApi();
    var continued = false;

    await pumpSaloniApp(
      tester,
      AboutSalonScreen(
        api: api,
        salonCode: 'RAHA-27',
        onContinue: () => continued = true,
      ),
    );
    await tester.pumpAndSettle();

    // اسم الصالون والنبذة والخدمات ظاهرة، بلا حاجة لتسجيل دخول.
    expect(find.text('صالون الراحة'), findsOneWidget);
    expect(find.textContaining('حلاقة شعر'), findsWidgets);
    expect(find.textContaining('واكس تصفيف'), findsWidgets);

    // زر «سجّل واحجز دوري» يستدعي onContinue (قد يحتاج تمريرًا للأسفل).
    final button = find.text('سجّل واحجز دوري');
    await tester.scrollUntilVisible(button, 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(continued, isTrue);
  });

  testWidgets('يعرض «حول الصالون» بلا زر متابعة حين تُعرض بعد الدخول', (tester) async {
    final api = FakeCustomerApi();
    await pumpSaloniApp(
      tester,
      AboutSalonScreen(api: api, salonCode: 'RAHA-27', showContinueCta: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('صالون الراحة'), findsOneWidget);
    expect(find.text('سجّل واحجز دوري'), findsNothing);
  });
}

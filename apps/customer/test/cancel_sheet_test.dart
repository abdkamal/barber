import 'package:customer/screens/tracking/cancel_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_customer_api.dart';
import 'support/pump_app.dart';

void main() {
  testWidgets('شاشة تأكيد الإلغاء تُلغي الحجز فقط بعد تأكيد صريح (ق29)', (tester) async {
    final api = FakeCustomerApi();
    var cancelledCallback = false;

    await pumpSaloniApp(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showCancelSheet(
                context: context,
                api: api,
                bookingId: 'bk-1',
                barberName: 'خالد الحربي',
                eta: DateTime.now().toUtc().add(const Duration(minutes: 25)),
                timezone: 'Asia/Riyadh',
                onCancelled: () => cancelledCallback = true,
              ),
              child: const Text('فتح شاشة الإلغاء'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('فتح شاشة الإلغاء'));
    await tester.pumpAndSettle();

    expect(find.text('إلغاء حجزك اليوم؟'), findsOneWidget);
    expect(api.cancelCalled, isFalse);

    // «الإبقاء على الحجز» يغلق الشاشة دون إلغاء.
    await tester.tap(find.text('الإبقاء على الحجز'));
    await tester.pumpAndSettle();
    expect(api.cancelCalled, isFalse);
    expect(find.text('إلغاء حجزك اليوم؟'), findsNothing);

    // إعادة الفتح والتأكيد الصريح يُلغي الحجز.
    await tester.tap(find.text('فتح شاشة الإلغاء'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('نعم، ألغِ الحجز'));
    await tester.pumpAndSettle();

    expect(api.cancelCalled, isTrue);
    expect(cancelledCallback, isTrue);
  });
}

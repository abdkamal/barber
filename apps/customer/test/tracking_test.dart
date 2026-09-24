import 'package:customer/screens/tracking/track_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_api/saloni_api.dart';

import 'fakes/fake_customer_api.dart';
import 'support/pump_app.dart';

Booking _booking({BookingStatus status = BookingStatus.waiting}) {
  final original = DateTime.now().toUtc().add(const Duration(minutes: 30));
  return Booking(
    id: 'bk-1',
    customerId: 'c-1',
    barberId: 'b-1',
    serviceIds: const ['svc-1'],
    kind: BookingKind.queue,
    status: status,
    originalEta: original,
    source: BookingSource.app,
  );
}

void main() {
  testWidgets('تعرض المتابعة الوقت المتوقع والأصلي والسبب وتقدّم الطابور، وتُبلغ السيرفر بما عُرض',
      (tester) async {
    final api = FakeCustomerApi();
    final booking = _booking();
    final eta = booking.originalEta.add(const Duration(minutes: 20)); // تغيّر أكثر من 30 د إجمالًا؟ نستخدم 20 هنا فقط لعرض الفارق.
    api.setCurrentBooking(
      CurrentBooking(
        booking: booking,
        eta: eta,
        originalEta: booking.originalEta,
        lastChangeReason: 'تمديد خدمة سابقة',
        progress: const BookingProgress(done: 3, ahead: 2),
        live: true,
        lastUpdateAt: DateTime.now().toUtc(),
      ),
    );

    await pumpSaloniApp(
      tester,
      TrackScreen(
        api: api,
        onChangeTime: (_) {},
        onCancel: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('كان متوقعًا'), findsOneWidget);
    expect(find.textContaining('تمديد خدمة سابقة'), findsWidgets);
    expect(find.text('تعديل الوقت'), findsOneWidget);
    expect(find.text('إلغاء الحجز'), findsOneWidget);

    // مرجع التنبيه الإلزامي (ق5): أُبلغ السيرفر بالوقت المعروض فعليًا.
    expect(api.lastMarkedSeenBookingId, 'bk-1');
    expect(api.lastMarkedSeenEta, eta);
  });

  testWidgets('تعرض حالة «كان متوقعًا» وشارة الاستدعاء عند status=called', (tester) async {
    final api = FakeCustomerApi();
    final booking = _booking(status: BookingStatus.called);
    api.setCurrentBooking(
      CurrentBooking(
        booking: booking,
        eta: booking.originalEta,
        originalEta: booking.originalEta,
        progress: const BookingProgress(done: 4, ahead: 0),
        live: true,
        lastUpdateAt: DateTime.now().toUtc(),
      ),
    );

    await pumpSaloniApp(
      tester,
      TrackScreen(api: api, onChangeTime: (_) {}, onCancel: (_) {}),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('اقترب دورك'), findsWidgets);
    // في حالة الاستدعاء لا تُعرض أزرار التعديل/الإلغاء.
    expect(find.text('تعديل الوقت'), findsNothing);
  });

  testWidgets('تعرض شريط «وقت تقديري» عند انقطاع الحلاق (live=false)', (tester) async {
    final api = FakeCustomerApi();
    final booking = _booking();
    api.setCurrentBooking(
      CurrentBooking(
        booking: booking,
        eta: booking.originalEta,
        originalEta: booking.originalEta,
        progress: const BookingProgress(done: 2, ahead: 2),
        live: false,
        lastUpdateAt: DateTime.now().toUtc().subtract(const Duration(minutes: 12)),
      ),
    );

    await pumpSaloniApp(
      tester,
      TrackScreen(api: api, onChangeTime: (_) {}, onCancel: (_) {}),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('لم يصلنا تحديث من الصالون'), findsWidgets);
    expect(find.textContaining('قبل 12 دقيقة'), findsWidgets);
  });
}

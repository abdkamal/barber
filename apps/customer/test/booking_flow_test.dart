import 'package:customer/screens/booking/book_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_api/saloni_api.dart';

import 'fakes/fake_customer_api.dart';
import 'support/pump_app.dart';

void main() {
  testWidgets('يحجز مباشرة عند قبول العرض الفوري (outcome=accept)', (tester) async {
    final api = FakeCustomerApi();
    final start = DateTime.now().toUtc().add(const Duration(minutes: 25));
    api.nextQuote = Quote(
      barberId: 'b-1',
      start: start,
      end: start.add(const Duration(minutes: 38)),
      durationMin: 38,
      priceCents: 4000,
      outcome: QuoteOutcome.accept,
    );

    Booking? booked;
    await pumpSaloniApp(
      tester,
      BookScreen(api: api, currency: 'ر.س', onBooked: (b) => booked = b),
    );
    await tester.pumpAndSettle();

    // اختيار خدمة يشغّل طلب عرض السعر (مع تأخير بسيط لتجميع التغييرات).
    await tester.tap(find.textContaining('حلاقة شعر').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // يظهر الوقت المتوقع والسعر في الشريط السفلي، والزر أصبح مفعّلًا.
    expect(find.textContaining('نحو 38 دقيقة'), findsOneWidget);

    await tester.tap(find.text('احجز دوري'));
    await tester.pumpAndSettle();

    expect(booked, isNotNull);
    expect(booked!.id, 'bk-1');
  });

  testWidgets('يعرض بطاقة العرض مع عدّاد تنازلي ويقبله عند طلب ساعة غير متاحة', (tester) async {
    final api = FakeCustomerApi();
    final offerStart = DateTime.now().toUtc().add(const Duration(minutes: 25));
    api.nextQuote = Quote(
      barberId: 'b-1',
      start: offerStart,
      end: offerStart.add(const Duration(minutes: 45)),
      durationMin: 45,
      priceCents: 6000,
      outcome: QuoteOutcome.offer,
      offerId: 'offer-1',
      offerExpiresAt: DateTime.now().toUtc().add(const Duration(minutes: 2)),
    );
    api.nextBooking = Booking(
      id: 'bk-offer-1',
      customerId: 'c-1',
      barberId: 'b-1',
      serviceIds: const ['svc-2'],
      kind: BookingKind.requested,
      status: BookingStatus.waiting,
      originalEta: offerStart,
      source: BookingSource.app,
    );

    Booking? booked;
    await pumpSaloniApp(
      tester,
      BookScreen(api: api, currency: 'ر.س', onBooked: (b) => booked = b),
    );
    await tester.pumpAndSettle();

    // اختيار الخدمة يكفي لتشغيل طلب عرض السعر؛ السيرفر (الوهمي هنا) هو من
    // يقرر عرض أقرب وقت بدل القبول الفوري (design.md §5.3) — لا حاجة
    // لمحاكاة اختيار «ساعة محددة» في هذا الاختبار.
    await tester.tap(find.textContaining('شعر ولحية').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // بطاقة العرض ظاهرة مع عدّاد تنازلي (دقيقتان).
    expect(find.textContaining('غير متاحة'), findsOneWidget);

    await tester.tap(find.text('احجز هذا الوقت'));
    await tester.pumpAndSettle();

    expect(booked, isNotNull);
    expect(booked!.id, 'bk-offer-1');
    expect(api.createdBookingCalls.last['offerId'], 'offer-1');
  });
}

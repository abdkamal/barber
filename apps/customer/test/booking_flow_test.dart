import 'package:customer/screens/booking/book_screen.dart';
import 'package:flutter/material.dart';
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
      BookScreen(api: api, currency: 'ر.س', timezone: 'Asia/Riyadh', onBooked: (b) => booked = b),
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
      BookScreen(api: api, currency: 'ر.س', timezone: 'Asia/Riyadh', onBooked: (b) => booked = b),
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

  testWidgets(
    'I5: طلب 00:30 عند دوام يعبر منتصف الليل (18:00–02:00) يُثبَّت على اليوم التالي بتوقيت الصالون',
    (tester) async {
      // دوام الحلاق: 18:00 اليوم — 02:00 غدًا بتوقيت الرياض.
      final workStart = DateTime.utc(2026, 9, 24, 15, 0); // 18:00 الرياض
      final workEnd = DateTime.utc(2026, 9, 25, 23, 0); // 02:00 الرياض غدًا
      final today = defaultTodayJson();
      (today['barbers'] as List)[0] = {
        'id': 'b-1',
        'name': 'خالد الحربي',
        'photoUrl': null,
        'dayState': 'connected',
        'nextAvailableStart': workStart.toIso8601String(),
        'queueLength': 2,
        'accepting': true,
        'workStart': workStart.toIso8601String(),
        'workEnd': workEnd.toIso8601String(),
      };
      final api = FakeCustomerApi(today: today);
      api.nextQuote = Quote(
        barberId: 'b-1',
        start: DateTime.utc(2026, 9, 24, 21, 30),
        end: DateTime.utc(2026, 9, 24, 22, 0),
        durationMin: 30,
        priceCents: 4000,
        outcome: QuoteOutcome.accept,
      );

      await pumpSaloniApp(
        tester,
        BookScreen(api: api, currency: 'ر.س', timezone: 'Asia/Riyadh', onBooked: (_) {}),
        surfaceSize: const Size(390, 1600),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('خالد الحربي'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ساعة محددة'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('اختر الساعة المطلوبة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('اختر الساعة المطلوبة'));
      await tester.pumpAndSettle();

      // يبدّل مربع الحوار لإدخال نصي (ساعة/دقيقة) بدل القرص — أسهل للاختبار.
      final keyboardToggle = find.byIcon(Icons.keyboard_outlined);
      if (keyboardToggle.evaluate().isNotEmpty) {
        await tester.tap(keyboardToggle);
        await tester.pumpAndSettle();
      }
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '12');
      await tester.enterText(fields.at(1), '30');
      // منتصف الليل بنمط 12 ساعة يحتاج تحديد «ص» صراحة.
      final amButton = find.text('AM');
      if (amButton.evaluate().isNotEmpty) await tester.tap(amButton.first);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('حلاقة شعر').first);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(api.lastQuoteRequestedAt, DateTime.utc(2026, 9, 24, 21, 30));
    },
  );
}

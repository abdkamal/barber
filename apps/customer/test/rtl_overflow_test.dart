import 'package:customer/screens/about_salon_screen.dart';
import 'package:customer/screens/booking/book_screen.dart';
import 'package:customer/screens/tracking/track_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_api/saloni_api.dart';

import 'fakes/fake_customer_api.dart';
import 'support/pump_app.dart';

void main() {
  testWidgets('لا فيض (overflow) بعرض 360 ومقياس نص 1.3 — حول الصالون', (tester) async {
    final api = FakeCustomerApi();
    await pumpSaloniApp(
      tester,
      AboutSalonScreen(api: api, salonCode: 'RAHA-27'),
      textScale: 1.3,
      surfaceSize: const Size(360, 800),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'لا فيض (overflow) بعرض 360 ومقياس نص 1.3 — الحجز',
    (tester) async {
      final api = FakeCustomerApi();
      await pumpSaloniApp(
        tester,
        BookScreen(api: api, currency: 'ر.س', timezone: 'Asia/Riyadh', onBooked: (_) {}),
        textScale: 1.3,
        surfaceSize: const Size(360, 800),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('لا فيض (overflow) بعرض 360 ومقياس نص 1.3 — المتابعة', (tester) async {
    final api = FakeCustomerApi();
    final booking = Booking(
      id: 'bk-1',
      customerId: 'c-1',
      barberId: 'b-1',
      serviceIds: const ['svc-1'],
      kind: BookingKind.queue,
      status: BookingStatus.waiting,
      originalEta: DateTime.now().toUtc().add(const Duration(minutes: 30)),
      source: BookingSource.app,
    );
    api.setCurrentBooking(
      CurrentBooking(
        booking: booking,
        eta: booking.originalEta,
        originalEta: booking.originalEta,
        progress: const BookingProgress(done: 2, ahead: 3),
        live: true,
        lastUpdateAt: DateTime.now().toUtc(),
      ),
    );

    await pumpSaloniApp(
      tester,
      TrackScreen(api: api, timezone: 'Asia/Riyadh', onChangeTime: (_) {}, onCancel: (_) {}),
      textScale: 1.3,
      surfaceSize: const Size(360, 800),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

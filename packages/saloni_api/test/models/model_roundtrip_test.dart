import 'package:saloni_api/saloni_api.dart';
import 'package:test/test.dart';

void main() {
  group('model JSON round-trips', () {
    test('SalonPublicProfile', () {
      final profile = SalonPublicProfile(
        code: 'ABC123',
        name: 'صالون الأمانة',
        logoUrl: 'https://x/logo.png',
        bio: 'أفضل صالون',
        address: 'الرياض',
        latitude: 24.7,
        longitude: 46.6,
        currency: 'SAR',
        timezone: 'Asia/Riyadh',
        contact: const SalonContactInfo(phone: '0500000000', socialLinks: ['https://x.com']),
        photos: const [SalonPhoto(url: 'https://x/1.png', order: 0)],
        workingHours: const [
          WorkingHoursEntry(weekday: 0, openMinutes: 540, closeMinutes: 1320),
        ],
        catalog: const [
          CatalogItem(
            id: 'c1',
            type: CatalogItemType.service,
            name: 'قص شعر',
            priceCents: 5000,
            order: 0,
            serviceId: 's1',
          ),
        ],
      );
      final decoded = SalonPublicProfile.fromJson(profile.toJson());
      expect(decoded.code, profile.code);
      expect(decoded.catalog.single.name, 'قص شعر');
      expect(decoded.workingHours.single.closeMinutes, 1320);
      expect(decoded.contact.socialLinks, ['https://x.com']);
    });

    test('Session', () {
      const session = Session(
        accessToken: 'a',
        refreshToken: 'r',
        role: UserRole.barber,
        salonCode: 'ABC123',
      );
      final decoded = Session.fromJson(session.toJson());
      expect(decoded.role, UserRole.barber);
      expect(decoded.refreshToken, 'r');
    });

    test('Booking with all statuses', () {
      for (final status in BookingStatus.values) {
        final booking = Booking(
          id: 'b1',
          customerId: 'c1',
          barberId: 'br1',
          serviceIds: const ['s1', 's2'],
          kind: BookingKind.queue,
          status: status,
          originalEta: DateTime.utc(2026, 9, 24, 10, 0),
          source: BookingSource.app,
        );
        final decoded = Booking.fromJson(booking.toJson());
        expect(decoded.status, status, reason: status.toString());
        expect(decoded.originalEta, booking.originalEta);
      }
    });

    test('Booking kind requested with requestedAt', () {
      final booking = Booking(
        id: 'b2',
        customerId: 'c1',
        barberId: 'br1',
        serviceIds: const ['s1'],
        kind: BookingKind.requested,
        requestedAt: DateTime.utc(2026, 9, 24, 11, 0),
        status: BookingStatus.waiting,
        originalEta: DateTime.utc(2026, 9, 24, 11, 5),
        source: BookingSource.barber,
        walkIn: true,
      );
      final decoded = Booking.fromJson(booking.toJson());
      expect(decoded.kind, BookingKind.requested);
      expect(decoded.walkIn, isTrue);
      expect(decoded.requestedAt, booking.requestedAt);
    });

    test('CurrentBooking', () {
      final current = CurrentBooking(
        booking: Booking(
          id: 'b1',
          customerId: 'c1',
          barberId: 'br1',
          serviceIds: const ['s1'],
          kind: BookingKind.queue,
          status: BookingStatus.waiting,
          originalEta: DateTime.utc(2026, 9, 24, 10, 0),
          source: BookingSource.app,
        ),
        eta: DateTime.utc(2026, 9, 24, 10, 15),
        originalEta: DateTime.utc(2026, 9, 24, 10, 0),
        lastChangeReason: 'تغيير الخدمة',
        progress: const BookingProgress(done: 2, ahead: 1),
        live: true,
        lastUpdateAt: DateTime.utc(2026, 9, 24, 9, 59),
      );
      final decoded = CurrentBooking.fromJson(current.toJson());
      expect(decoded.progress.done, 2);
      expect(decoded.live, isTrue);
      expect(decoded.lastChangeReason, 'تغيير الخدمة');
    });

    test('Payment', () {
      final payment = Payment(
        id: 'p1',
        bookingId: 'b1',
        amountCents: 5000,
        status: PaymentStatus.awaitingConfirmation,
      );
      final decoded = Payment.fromJson(payment.toJson());
      expect(decoded.status, PaymentStatus.awaitingConfirmation);
    });

    test('DeviceEvent for every DeviceEventType', () {
      for (final type in DeviceEventType.values) {
        final event = DeviceEvent(
          id: 'e1',
          deviceSeq: 3,
          type: type,
          bookingId: 'b1',
          occurredAt: DateTime.utc(2026, 9, 24, 10, 0),
          approximate: false,
          payload: const {'k': 'v'},
        );
        final decoded = DeviceEvent.fromJson(event.toJson());
        expect(decoded.type, type, reason: type.toString());
        expect(decoded.payload['k'], 'v');
      }
    });

    test('StaffToday', () {
      final staffToday = StaffToday(
        queue: [
          Booking(
            id: 'b1',
            customerId: 'c1',
            barberId: 'br1',
            serviceIds: const ['s1'],
            kind: BookingKind.queue,
            status: BookingStatus.waiting,
            originalEta: DateTime.utc(2026, 9, 24, 10, 0),
            source: BookingSource.app,
          ),
        ],
        services: const [
          Service(id: 's1', name: 'قص', baseDurationMin: 20, priceCents: 3000),
        ],
        breaks: [
          BreakPeriod(
            id: 'br1',
            kind: BreakKind.prayer,
            start: DateTime.utc(2026, 9, 24, 12, 0),
            end: DateTime.utc(2026, 9, 24, 12, 20),
          ),
        ],
        settings: const {'callLeadMinutes': 20},
        serverTime: DateTime.utc(2026, 9, 24, 9, 0),
        seq: 42,
      );
      final decoded = StaffToday.fromJson(staffToday.toJson());
      expect(decoded.seq, 42);
      expect(decoded.queue.single.id, 'b1');
      expect(decoded.breaks.single.kind, BreakKind.prayer);
      expect(decoded.settings['callLeadMinutes'], 20);
    });

    test('SyncPullResult', () {
      final result = SyncPullResult.fromJson({
        'changes': [
          {
            'seq': 5,
            'type': 'booking_created',
            'bookingId': 'b1',
            'data': {'x': 1},
            'occurredAt': '2026-09-24T09:00:00Z',
          },
        ],
        'seq': 5,
        'serverTime': '2026-09-24T09:00:01Z',
      });
      expect(result.changes.single.seq, 5);
      expect(result.seq, 5);
    });

    test('ApiError.fromJson parses server error shape', () {
      final error = ApiError.fromJson({
        'error': {'code': 'SLOT_UNAVAILABLE', 'message': 'الوقت غير متاح'},
      }, statusCode: 409);
      expect(error.code, 'SLOT_UNAVAILABLE');
      expect(error.message, 'الوقت غير متاح');
      expect(error.statusCode, 409);
    });
  });
}

import 'package:saloni_api/saloni_api.dart';
import 'package:test/test.dart';

void main() {
  group('model JSON round-trips', () {
    test('SalonPublicProfile parses the server shape', () {
      final json = {
        'code': 'ABC123',
        'name': 'صالون الأمانة',
        'timezone': 'Asia/Riyadh',
        'currency': 'SAR',
        'about': 'أفضل صالون',
        'logo': '/v1/media/ABC123/logo.webp',
        'address': 'الرياض',
        'location': {'lat': 24.7, 'lng': 46.6},
        'contact': {
          'phone': '0500000000',
          'whatsapp': null,
          'social': [
            {'platform': 'instagram', 'url': 'https://instagram.com/x'}
          ],
        },
        'photos': [
          {'id': 'p1', 'url': '/v1/media/ABC123/1.webp', 'position': 0}
        ],
        'hours': [
          {'weekday': 0, 'opensAt': '09:00', 'closesAt': '22:00', 'crossesMidnight': false},
          {'weekday': 5, 'opensAt': '16:00', 'closesAt': '01:00', 'crossesMidnight': true},
        ],
        'openNow': true,
        'services': [
          {'id': 's1', 'name': 'قص', 'durationMin': 30, 'price': 5000}
        ],
        'catalog': [
          {
            'id': 'c1',
            'kind': 'service',
            'name': 'قص شعر',
            'description': null,
            'features': ['غسيل'],
            'price': 5000,
            'photo': null,
            'serviceId': 's1',
          },
          {
            'id': 'c2',
            'kind': 'product',
            'name': 'زيت',
            'features': [],
            'price': null,
            'photo': '/v1/media/ABC123/2.webp',
            'serviceId': null,
          },
        ],
      };
      final profile = SalonPublicProfile.fromJson(json);
      expect(profile.about, 'أفضل صالون');
      expect(profile.logoUrl, '/v1/media/ABC123/logo.webp');
      expect(profile.latitude, 24.7);
      expect(profile.contact.socialLinks.single.platform, 'instagram');
      expect(profile.photos.single.position, 0);
      expect(profile.hours.first.closeMinutes, 22 * 60);
      expect(profile.hours.last.closeMinutes, 25 * 60);
      expect(profile.hours.first.dartWeekday, DateTime.sunday);
      expect(profile.openNow, isTrue);
      expect(profile.services.single.baseDurationMin, 30);
      expect(profile.services.single.priceCents, 5000);
      expect(profile.catalog.first.type, CatalogItemType.service);
      expect(profile.catalog.last.priceCents, isNull);
      final again = SalonPublicProfile.fromJson(profile.toJson());
      expect(again.catalog.map((c) => c.name), ['قص شعر', 'زيت']);
      expect(again.hours.last.crossesMidnight, isTrue);
    });

    test('Session', () {
      const session = Session(
        accessToken: 'a',
        refreshToken: 'r',
        role: UserRole.barber,
        salon: SalonInfo(code: 'ABC123'),
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

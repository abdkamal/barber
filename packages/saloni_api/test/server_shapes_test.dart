import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saloni_api/saloni_api.dart';
import 'package:test/test.dart';

/// Fixtures copied from the server DTOs (server/src/scheduling/dto.ts,
/// staff-day.service.ts, booking.service.ts, auth.service.ts,
/// manager-queues.service.ts) — the client must parse them as sent.
Map<String, dynamic> bookingDto({
  String id = '11111111-1111-4111-8111-111111111111',
  String status = 'waiting',
  bool phone = false,
}) =>
    {
      'id': id,
      'customerId': 'c1',
      'barberId': 'br1',
      'serviceIds': ['s1', 's2'],
      'kind': 'queue',
      'requestedAt': null,
      'status': status,
      'queuePosition': 2,
      'originalEta': '2026-09-24T10:00:00.000Z',
      'lastShownEta': null,
      'postponementUsed': false,
      'actualStart': null,
      'actualEnd': null,
      'source': 'app',
      'walkIn': false,
      'createdAt': '2026-09-24T08:00:00.000Z',
      'workDate': '2026-09-24',
      'customerName': 'سالم',
      if (phone) 'customerPhone': '+966500000000',
      'services': [
        {'id': 's1', 'name': 'قص', 'priceCents': 3000, 'baseDurationMin': 20},
        {'id': 's2', 'name': 'لحية', 'priceCents': 2000, 'baseDurationMin': 10},
      ],
      'priceCents': 5000,
      'estimatedDurationMin': 35,
      'eta': '2026-09-24T10:20:00.000Z',
      'etaEnd': '2026-09-24T10:55:00.000Z',
      'calledAt': null,
      'offerExpiresAt': null,
      'lastChangeReason': 'تأخر الزبون قبلك',
      'serveLate': false,
      'needsReview': false,
    };

Map<String, dynamic> sessionJson({String access = 'a1', String refresh = 'r1'}) => {
      'accessToken': access,
      'accessTokenExpiresIn': 900,
      'refreshToken': refresh,
      'role': 'barber',
      'salon': {
        'code': 'RAHA-27',
        'name': 'صالون الراحة',
        'status': 'active',
        'timezone': 'Asia/Riyadh',
        'currency': 'SAR',
      },
      'account': {'id': 'st1', 'name': 'خالد'},
    };

http.Response jsonResponse(Object? body, int status) => http.Response.bytes(
      body == null ? const [] : utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  group('server shapes', () {
    test('Session: salon and account objects', () {
      final s = Session.fromJson(sessionJson());
      expect(s.salonCode, 'RAHA-27');
      expect(s.salon.name, 'صالون الراحة');
      expect(s.salon.currency, 'SAR');
      expect(s.salon.isActive, isTrue);
      expect(s.account!.name, 'خالد');
      expect(s.accessTokenExpiresIn, 900);
      final again = Session.fromJson(s.toJson());
      expect(again.salon.timezone, 'Asia/Riyadh');
    });

    test('Session: legacy stored session with salon as a string', () {
      final s = Session.fromJson(
          {'accessToken': 'a', 'refreshToken': 'r', 'role': 'customer', 'salon': 'OLD-1'});
      expect(s.salonCode, 'OLD-1');
      expect(s.account, isNull);
    });

    test('SalonRegistration', () {
      final r = SalonRegistration.fromJson({
        'salon': {
          'code': 'NEW-1',
          'name': 'ن',
          'status': 'pending_activation',
          'timezone': 'Asia/Riyadh',
          'currency': 'SAR'
        },
        'session': {...sessionJson(), 'role': 'manager'},
      });
      expect(r.salon.pendingActivation, isTrue);
      expect(r.session.role, UserRole.manager);
    });

    test('Booking: all server fields', () {
      final b = Booking.fromJson(bookingDto(phone: true));
      expect(b.customerName, 'سالم');
      expect(b.customerPhone, '+966500000000');
      expect(b.services.map((s) => s.name), ['قص', 'لحية']);
      expect(b.priceCents, 5000);
      expect(b.estimatedDurationMin, 35);
      expect(b.durationMin, 35);
      expect(b.eta, DateTime.utc(2026, 9, 24, 10, 20));
      expect(b.etaEnd, DateTime.utc(2026, 9, 24, 10, 55));
      expect(b.workDate, '2026-09-24');
      expect(b.lastChangeReason, isNotNull);
      expect(b.serviceNames, 'قص + لحية');
      final again = Booking.fromJson(b.toJson());
      expect(again.customerPhone, b.customerPhone);
      expect(again.services.last.baseDurationMin, 10);
    });

    test('BookingStatus.expired and BreakKind.walkInOnly', () {
      expect(Booking.fromJson(bookingDto(status: 'expired')).status,
          BookingStatus.expired);
      expect(BreakKind.fromWire('walk_in_only'), BreakKind.walkInOnly);
      expect(BreakKind.walkInOnly.toWire(), 'walk_in_only');
      expect(BreakKind.walkInOnly.deviceStartable, isFalse);
    });

    test('StaffToday with day, walkInOnly and closingWarnings', () {
      final t = StaffToday.fromJson({
        'day': {
          'workDate': '2026-09-24',
          'workStart': '2026-09-24T06:00:00.000Z',
          'workEnd': '2026-09-24T19:00:00.000Z',
          'state': 'connected',
          'firstConnectedAt': '2026-09-24T06:01:00.000Z',
        },
        'queue': [bookingDto(phone: true)],
        'breaks': [
          {
            'id': 'x1',
            'kind': 'prayer',
            'start': '2026-09-24T09:00:00.000Z',
            'end': '2026-09-24T09:20:00.000Z',
            'open': true
          }
        ],
        'walkInOnly': [
          {'id': 'w1', 'start': '2026-09-24T13:00:00.000Z', 'end': '2026-09-24T14:00:00.000Z'}
        ],
        'closingWarnings': ['11111111-1111-4111-8111-111111111111'],
        'services': [
          {'id': 's1', 'name': 'قص', 'baseDurationMin': 20, 'priceCents': 3000, 'active': true}
        ],
        'settings': {'callAheadMinutes': 20, 'overrunAlertPercent': 100},
        'serverTime': '2026-09-24T09:05:00.000Z',
        'seq': 42,
      });
      expect(t.day!.state, BarberDayState.connected);
      expect(t.queue.single.customerPhone, isNotNull);
      expect(t.openBreak!.kind, BreakKind.prayer);
      expect(t.walkInOnly.single.contains(DateTime.utc(2026, 9, 24, 13, 30)), isTrue);
      expect(t.closingWarnings, hasLength(1));
      expect(t.seq, 42);
    });

    test('StaffToday with no shift (day: null)', () {
      final t = StaffToday.fromJson({
        'day': null,
        'queue': [],
        'breaks': [],
        'walkInOnly': [],
        'closingWarnings': [],
        'services': [],
        'settings': {},
        'serverTime': '2026-09-24T09:05:00.000Z',
        'seq': 1,
      });
      expect(t.hasShift, isFalse);
    });

    test('CustomerToday', () {
      final t = CustomerToday.fromJson({
        'serverTime': '2026-09-24T09:00:00.000Z',
        'accountStatus': 'pending',
        'currency': 'SAR',
        'services': [
          {'id': 's1', 'name': 'قص', 'baseDurationMin': 20, 'priceCents': 3000, 'active': true}
        ],
        'barbers': [
          {
            'id': 'br1',
            'name': 'خالد',
            'photoUrl': null,
            'dayState': 'not_connected_yet',
            'nextAvailableStart': null,
            'queueLength': 0,
            'accepting': false,
            'workStart': null,
            'workEnd': null
          }
        ],
      });
      expect(t.accountPending, isTrue);
      expect(t.barbers.single.accepting, isFalse);
      expect(t.services.single.priceCents, 3000);
    });

    test('HistoryVisit', () {
      final v = HistoryVisit.fromJson({
        ...bookingDto(status: 'done'),
        'barberName': 'خالد',
        'payment': {'status': 'confirmed', 'amountCents': 5000},
      });
      expect(v.booking.status, BookingStatus.done);
      expect(v.barberName, 'خالد');
      expect(v.payment!.status, PaymentStatus.confirmed);
      final none = HistoryVisit.fromJson({...bookingDto(status: 'cancelled'), 'barberName': 'x', 'payment': null});
      expect(none.payment, isNull);
    });

    test('Payment from /staff/payments', () {
      final p = Payment.fromJson({
        'id': 'p1',
        'bookingId': 'b1',
        'amountCents': 5000,
        'status': 'awaiting_confirmation',
        'confirmedBy': null,
        'confirmedAt': null,
        'barberId': 'br1',
        'customerName': 'سالم',
        'workDate': '2026-09-24',
        'finishedAt': '2026-09-24T10:40:00.000Z',
        'createdAt': '2026-09-24T10:40:00.000Z',
      });
      expect(p.customerName, 'سالم');
      expect(p.finishedAt, isNotNull);
      expect(p.confirmedAmountCents, isNull);
      expect(p.discrepancy, isFalse);
    });

    test('Payment with confirmedAmountCents/discrepancy (مراجعة المرحلة 6)', () {
      final p = Payment.fromJson({
        'id': 'p1',
        'bookingId': 'b1',
        'amountCents': 5000,
        'confirmedAmountCents': 4500,
        'discrepancy': true,
        'status': 'confirmed',
        'confirmedBy': 'st1',
        'confirmedAt': '2026-09-24T10:45:00.000Z',
      });
      expect(p.amountCents, 5000);
      expect(p.confirmedAmountCents, 4500);
      expect(p.discrepancy, isTrue);
    });

    test('StaffImpact', () {
      final i = StaffImpact.fromJson({
        'bookingId': 'b1',
        'oldDurationMin': 20,
        'newDurationMin': 45,
        'oldPriceCents': 3000,
        'newPriceCents': 6000,
        'changes': [
          {
            'bookingId': 'b2',
            'customerName': 'فهد',
            'before': '2026-09-24T10:20:00.000Z',
            'after': '2026-09-24T10:45:00.000Z',
            'deltaMin': 25,
            'pastClosing': false,
            'notify': true
          }
        ],
        'pastClosing': [
          {'bookingId': 'b3', 'customerName': null, 'end': '2026-09-24T19:10:00.000Z', 'newlyPastClosing': true}
        ],
        'workEnd': '2026-09-24T19:00:00.000Z',
      });
      expect(i.changes.single.notify, isTrue);
      expect(i.pastClosing.single.newlyPastClosing, isTrue);
      expect(i.newPriceCents, 6000);
    });

    test('ManagerQueues', () {
      final q = ManagerQueues.fromJson({
        'serverTime': '2026-09-24T09:00:00.000Z',
        'seq': 7,
        'barbers': [
          {'id': 'b1', 'name': 'أ', 'role': 'barber', 'day': null, 'accepting': false, 'queue': []},
          {
            'id': 'b2',
            'name': 'ب',
            'role': 'manager',
            'day': {
              'workDate': '2026-09-24',
              'workStart': '2026-09-24T06:00:00.000Z',
              'workEnd': '2026-09-24T19:00:00.000Z',
              'state': 'disconnected',
              'firstConnectedAt': null
            },
            'accepting': true,
            'queue': [bookingDto(phone: true)],
          },
        ],
      });
      expect(q.barbers.first.day, isNull);
      expect(q.barbers.last.queue.single.customerName, 'سالم');
      expect(q.barbers.last.day!.state, BarberDayState.disconnected);
    });

    test('PhoneDispute', () {
      final d = PhoneDispute.fromJson({
        'phone': '+966500000000',
        'accountId': 'a1',
        'walkIns': [
          {'id': 'w1', 'name': 'سالم', 'createdAt': '2026-09-01T10:00:00.000Z'},
          {'id': 'w2', 'name': 'سالم', 'createdAt': '2026-09-02T10:00:00.000Z'},
        ],
      });
      expect(d.walkIns, hasLength(2));
    });

    test('ApiError keeps details; change-time offer and transfer alternatives', () {
      final e = ApiError.fromJson({
        'error': {
          'code': 'SLOT_UNAVAILABLE',
          'message': 'الساعة غير متاحة',
          'details': {
            'offer': {
              'barberId': 'br1',
              'barberName': 'خالد',
              'start': '2026-09-24T11:00:00.000Z',
              'end': '2026-09-24T11:30:00.000Z',
              'durationMin': 30,
              'price': 3000,
              'outcome': 'offer',
              'offerId': 'o1',
              'offerExpiresAt': '2026-09-24T09:07:00.000Z',
            }
          }
        }
      }, statusCode: 409);
      expect(e.details, isA<Map>());
      expect(e.changeTimeOffer!.offerId, 'o1');
      expect(e.changeTimeOffer!.barberName, 'خالد');
      expect(e.transferAlternatives, isEmpty);

      final t = ApiError.fromJson({
        'error': {
          'code': 'TRANSFER_NO_SLOT',
          'message': 'لا يتسع',
          'details': {
            'nearest': null,
            'alternatives': [
              {'barberId': 'b3', 'barberName': 'ج', 'start': '2026-09-24T11:00:00.000Z', 'end': '2026-09-24T11:30:00.000Z'}
            ]
          }
        }
      });
      expect(t.transferAlternatives.single.barberName, 'ج');
      expect(t.changeTimeOffer, isNull);
      expect(const ApiError(code: 'ACCOUNT_PENDING', message: '').isAccountPending, isTrue);
    });
  });

  group('push notifications', () {
    test('known and new types parse; unknown is tolerated', () {
      final t = PushNotification.fromData(
          {'type': 'transferred', 'bookingId': 'b1', 'eta': '2026-09-24T10:00:00.000Z', 'barberId': 'br2'},
          title: 'نُقل حجزك');
      expect(t.kind, NotificationKind.transferred);
      expect(t.kind.affectsQueue, isTrue);
      expect(t.data['barberId'], 'br2');
      final s = PushNotification.fromData({'type': 'base_duration_suspect'});
      expect(s.kind, NotificationKind.baseDurationSuspect);
      expect(s.kind.forManager, isTrue);
      expect(PushNotification.fromData({'type': 'something_new'}).kind, NotificationKind.unknown);
    });
  });

  group('ApiClient against server shapes', () {
    late List<http.BaseRequest> seen;
    late Map<String, http.Response Function(http.Request)> routes;

    ApiClient client() {
      seen = [];
      return ApiClient(
        baseUrl: 'https://api.example.test',
        tokenStore: InMemoryTokenStore(),
        httpClient: MockClient((req) async {
          seen.add(req);
          final key = '${req.method} ${req.url.path}';
          final h = routes[key];
          if (h == null) return jsonResponse({'error': {'code': 'NOT_FOUND', 'message': key}}, 404);
          return h(req);
        }),
      );
    }

    setUp(() => routes = {});

    test('getCurrentBooking: {booking: null} → null', () async {
      routes['GET /v1/bookings/current'] =
          (_) => jsonResponse({'booking': null, 'serverTime': '2026-09-24T09:00:00.000Z'}, 200);
      final c = client();
      await c.setSession(Session.fromJson(sessionJson()), rememberMe: false);
      expect(await c.getCurrentBooking(), isNull);
    });

    test('getCurrentBooking: legacy 404 NO_ACTIVE_BOOKING → null', () async {
      routes['GET /v1/bookings/current'] = (_) =>
          jsonResponse({'error': {'code': 'NO_ACTIVE_BOOKING', 'message': 'لا يوجد'}}, 404);
      final c = client();
      await c.setSession(Session.fromJson(sessionJson()), rememberMe: false);
      expect(await c.getCurrentBooking(), isNull);
    });

    test('getCurrentBooking: full server shape', () async {
      routes['GET /v1/bookings/current'] = (_) => jsonResponse({
            'booking': bookingDto(),
            'eta': '2026-09-24T10:20:00.000Z',
            'etaEnd': '2026-09-24T10:55:00.000Z',
            'originalEta': '2026-09-24T10:00:00.000Z',
            'lastChangeReason': 'نص',
            'lastChangeReasonCode': 'transferred',
            'status': 'waiting',
            'progress': {'done': 1, 'ahead': 2},
            'live': false,
            'dayState': 'disconnected',
            'lastUpdateAt': '2026-09-24T09:50:00.000Z',
            'barber': {'id': 'br1', 'name': 'خالد'},
            'serverTime': '2026-09-24T09:55:00.000Z',
          }, 200);
      final c = client();
      await c.setSession(Session.fromJson(sessionJson()), rememberMe: false);
      final cur = (await c.getCurrentBooking())!;
      expect(cur.barber!.name, 'خالد');
      expect(cur.dayState, BarberDayState.disconnected);
      expect(cur.lastChangeReasonCode, 'transferred');
      expect(cur.etaEnd, isNotNull);
      expect(cur.status, BookingStatus.waiting);
    });

    test('network failure during refresh does not sign out and is retryable', () async {
      var failRefresh = true;
      routes['GET /v1/staff/payments'] = (req) => req.headers['Authorization'] == 'Bearer a2'
          ? jsonResponse([], 200)
          : jsonResponse({'error': {'code': 'UNAUTHENTICATED', 'message': 'x'}}, 401);
      routes['POST /v1/auth/refresh'] = (_) {
        if (failRefresh) throw const SocketLikeException();
        return jsonResponse(sessionJson(access: 'a2', refresh: 'r2'), 200);
      };
      final store = InMemoryTokenStore();
      seen = [];
      final c = ApiClient(
        baseUrl: 'https://api.example.test',
        tokenStore: store,
        httpClient: MockClient((req) async {
          final h = routes['${req.method} ${req.url.path}']!;
          return h(req);
        }),
      );
      await c.setSession(Session.fromJson(sessionJson()), rememberMe: false);
      var signedOut = 0;
      final sub = c.onSignedOut.listen((_) => signedOut++);

      await expectLater(c.getStaffPayments(),
          throwsA(isA<ApiError>().having((e) => e.isNetwork, 'isNetwork', isTrue)));
      await Future<void>.delayed(Duration.zero);
      expect(signedOut, 0);
      expect(await store.read(), isNotNull, reason: 'session must be kept');

      failRefresh = false;
      expect(await c.getStaffPayments(), isEmpty);
      expect((await store.read())!.refreshToken, 'r2');
      await sub.cancel();
    });

    test('5xx during refresh does not sign out', () async {
      routes['GET /v1/staff/payments'] =
          (_) => jsonResponse({'error': {'code': 'UNAUTHENTICATED', 'message': 'x'}}, 401);
      routes['POST /v1/auth/refresh'] =
          (_) => jsonResponse({'error': {'code': 'INTERNAL_ERROR', 'message': 'x'}}, 500);
      final c = client();
      await c.setSession(Session.fromJson(sessionJson()), rememberMe: false);
      var signedOut = 0;
      c.onSignedOut.listen((_) => signedOut++);
      await expectLater(c.getStaffPayments(),
          throwsA(isA<ApiError>().having((e) => e.code, 'code', 'INTERNAL_ERROR')));
      await Future<void>.delayed(Duration.zero);
      expect(signedOut, 0);
    });

    test('multipart photo upload', () async {
      routes['POST /v1/manager/photos'] = (_) => jsonResponse(
          {'id': 'p1', 'path': 'x/1.webp', 'url': '/v1/media/RAHA-27/1.webp', 'position': 0}, 201);
      final c = client();
      await c.setSession(Session.fromJson(sessionJson()), rememberMe: false);
      final r = await c.uploadManagerPhoto(bytes: [1, 2, 3], filename: 'a.jpg');
      expect(r.url, '/v1/media/RAHA-27/1.webp');
      expect(c.resolveMediaUrl(r.url), 'https://api.example.test/v1/media/RAHA-27/1.webp');
      final req = seen.single as http.Request;
      expect(req.headers['content-type'], startsWith('multipart/form-data'));
      final body = utf8.decode(req.bodyBytes, allowMalformed: true);
      expect(body, contains('name="file"; filename="a.jpg"'));
      expect(body, contains('image/jpeg'));
    });

    test('schedules PUT, DELETE with staffId, break/absence deletes, reports dates', () async {
      routes['PUT /v1/manager/schedules'] = (req) {
        final b = jsonDecode(req.body) as Map;
        return jsonResponse({...b}, 200);
      };
      routes['DELETE /v1/manager/schedules/3'] = (_) => jsonResponse({'ok': true}, 200);
      routes['DELETE /v1/manager/breaks/b1'] = (_) => jsonResponse({'ok': true}, 200);
      routes['DELETE /v1/manager/absences/a1'] = (_) => jsonResponse({'ok': true}, 200);
      routes['GET /v1/manager/reports'] = (_) => jsonResponse({'range': {}}, 200);
      routes['POST /v1/manager/breaks'] = (_) => jsonResponse([{'id': 'b1'}, {'id': 'b2'}], 201);
      final c = client();
      await c.setSession(Session.fromJson(sessionJson()), rememberMe: false);
      final s = await c.putManagerSchedule(staffId: null, weekday: 0, opensAt: '09:00', closesAt: '22:00');
      expect(s['staffId'], isNull);
      await c.deleteManagerSchedule(3, staffId: 'st1');
      expect(seen.last.url.queryParameters['staffId'], 'st1');
      await c.deleteManagerBreak('b1');
      await c.deleteManagerAbsence('a1');
      expect(await c.createManagerBreak({'staffId': 'all'}), hasLength(2));
      await c.getManagerReports(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 24, 23, 59));
      expect(seen.last.url.queryParameters, {'from': '2026-09-01', 'to': '2026-09-24'});
      expect(serverWeekday(DateTime.sunday), 0);
      expect(serverWeekday(DateTime.saturday), 6);
    });

    test('transfer and phone disputes', () async {
      routes['POST /v1/manager/bookings/b1/transfer'] = (req) {
        expect(req.headers['Idempotency-Key'], isNotNull);
        expect(jsonDecode(req.body), {'toBarberId': 'br2'});
        return jsonResponse({...bookingDto(), 'barberId': 'br2'}, 200);
      };
      routes['GET /v1/manager/phone-disputes'] = (_) => jsonResponse([
            {'phone': '1', 'accountId': null, 'walkIns': []}
          ], 200);
      routes['POST /v1/manager/phone-disputes/a1/resolve'] = (req) {
        expect(jsonDecode(req.body), {'walkInId': 'w1'});
        return jsonResponse({'ok': true}, 200);
      };
      final c = client();
      await c.setSession(Session.fromJson(sessionJson()), rememberMe: false);
      expect((await c.transferBooking(bookingId: 'b1', toBarberId: 'br2')).barberId, 'br2');
      expect((await c.getPhoneDisputes()).single.accountId, isNull);
      await c.resolvePhoneDispute(accountId: 'a1', walkInId: 'w1');
    });

    test('phone dispute additive fields (accountStatus/linkedWalkInId/proposedWalkInId — H2)', () async {
      routes['GET /v1/manager/phone-disputes'] = (_) => jsonResponse([
            {
              'phone': '0500000000',
              'accountId': 'a1',
              'accountStatus': 'suspended',
              'linkedWalkInId': 'w0',
              'proposedWalkInId': 'w2',
              'walkIns': [
                {'id': 'w1', 'name': 'حاضر', 'createdAt': '2026-09-24T09:00:00.000Z'},
              ],
            }
          ], 200);
      final c = client();
      await c.setSession(Session.fromJson(sessionJson()), rememberMe: false);
      final d = (await c.getPhoneDisputes()).single;
      expect(d.accountStatus, 'suspended');
      expect(d.linkedWalkInId, 'w0');
      expect(d.proposedWalkInId, 'w2');
      expect(d.walkIns.single.name, 'حاضر');
    });

    test('customer phone/link management (H2): unlink, reassign phone, release phone', () async {
      routes['POST /v1/manager/customers/c1/unlink-walkin'] = (_) => jsonResponse({'ok': true}, 200);
      routes['PUT /v1/manager/customers/c1/phone'] = (req) {
        expect(jsonDecode(req.body), {'phone': '0511111111'});
        return jsonResponse({'id': 'c1', 'phone': '0511111111'}, 200);
      };
      routes['POST /v1/manager/customers/c1/release-phone'] = (_) => jsonResponse({'ok': true}, 200);
      final c = client();
      await c.setSession(Session.fromJson(sessionJson()), rememberMe: false);
      await c.unlinkWalkInRecord('c1');
      final updated = await c.updateCustomerPhone('c1', '0511111111');
      expect(updated['phone'], '0511111111');
      await c.releaseCustomerPhone('c1');
    });

    test('heartbeat sends no queueDigest', () async {
      routes['POST /v1/heartbeat'] = (req) {
        expect(jsonDecode(req.body), {'deviceSeq': 4});
        return jsonResponse({
          'serverTime': '2026-09-24T09:00:00.000Z',
          'seq': 3,
          'workDate': '2026-09-24',
          'state': 'connected',
          'reconnected': true
        }, 200);
      };
      final c = client();
      await c.setSession(Session.fromJson(sessionJson()), rememberMe: false);
      final hb = await c.heartbeat(deviceSeq: 4);
      expect(hb.reconnected, isTrue);
    });
  });
}

/// A transport failure thrown by the HTTP layer (like a SocketException).
class SocketLikeException implements Exception {
  const SocketLikeException();
  @override
  String toString() => 'SocketException: connection refused';
}

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saloni_api/saloni_api.dart';
import 'package:saloni_api/staff_sync.dart';
import 'package:test/test.dart';

/// ق40: رفع المدير لإجراءات حساب موقوف من جهازه.
DeviceEvent _event(int deviceSeq) => DeviceEvent(
      id: 'evt-$deviceSeq',
      deviceSeq: deviceSeq,
      type: DeviceEventType.serviceFinished,
      bookingId: 'b$deviceSeq',
      occurredAt: DateTime.utc(2026, 9, 24, 10, 0, deviceSeq),
      approximate: deviceSeq.isOdd,
    );

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

ApiClient _manager(Future<http.Response> Function(http.Request r) handler) {
  final client = ApiClient(
    baseUrl: 'https://api.example.test',
    tokenStore: InMemoryTokenStore(),
    httpClient: MockClient(handler),
  );
  client.setSession(
    const Session(
      accessToken: 'mgr',
      refreshToken: 'r',
      role: UserRole.manager,
      salon: SalonInfo(code: 'ABC123'),
    ),
    rememberMe: false,
  );
  return client;
}

/// يحاكي السيرفر: ما وقع قبل الثانية 3 يُطبّق، والباقي بعد الإيقاف.
Map<String, dynamic> _answer(List events) {
  final results = [
    for (final e in events)
      (e['deviceSeq'] as int) < 3
          ? {'eventId': e['id'], 'result': 'applied'}
          : {'eventId': e['id'], 'result': 'rejected_after_suspension', 'reason': 'AFTER_SUSPENSION'},
  ];
  return {
    'staffId': 'barber-9',
    'suspendedAt': '2026-09-24T10:00:03.000Z',
    'results': results,
    'summary': {
      'applied': results.where((r) => r['result'] == 'applied').length,
      'duplicate': 0,
      'rejectedAfterSuspension': results.where((r) => r['result'] != 'applied').length,
      'rejectedInvalid': 0,
    },
  };
}

void main() {
  group('ApiClient — ق40', () {
    test('recoverStaffEvents posts the events in deviceSeq order and parses the report', () async {
      http.Request? seen;
      final api = _manager((r) async {
        seen = r;
        return _json(_answer((jsonDecode(r.body) as Map)['events'] as List));
      });
      final report = await api.recoverStaffEvents(staffId: 'barber-9', events: [_event(4), _event(1), _event(2)]);
      expect(seen!.method, 'POST');
      expect(seen!.url.path, '/v1/manager/staff/barber-9/recover-events');
      expect(seen!.headers['Authorization'], 'Bearer mgr');
      final sent = ((jsonDecode(seen!.body) as Map)['events'] as List).cast<Map>();
      expect(sent.map((e) => e['deviceSeq']), [1, 2, 4]);
      expect(sent.first['approximate'], isTrue);
      expect(sent.first['occurredAt'], '2026-09-24T10:00:01.000Z');
      expect(report.staffId, 'barber-9');
      expect(report.suspendedAt, DateTime.utc(2026, 9, 24, 10, 0, 3));
      expect(report.results.map((o) => o.result), [
        RecoveryResult.applied,
        RecoveryResult.applied,
        RecoveryResult.rejectedAfterSuspension,
      ]);
      expect(report.results.last.reason, 'AFTER_SUSPENSION');
      expect(report.summary.applied, 2);
      expect(report.summary.rejectedAfterSuspension, 1);
      expect(report.summary.accepted, 2);
      expect(report.summary.rejected, 1);
    });

    test('more than 200 events are sent in chunks and the results merged', () async {
      final sizes = <int>[];
      final api = _manager((r) async {
        final events = (jsonDecode(r.body) as Map)['events'] as List;
        sizes.add(events.length);
        return _json(_answer(events));
      });
      final report = await api.recoverStaffEvents(
          staffId: 'barber-9', events: [for (var i = 1; i <= 205; i++) _event(i)]);
      expect(sizes, [200, 5]);
      expect(report.results, hasLength(205));
      expect(report.summary.applied, 2);
      expect(report.summary.rejectedAfterSuspension, 203);
    });

    test('an empty outbox sends nothing', () async {
      var calls = 0;
      final api = _manager((r) async {
        calls++;
        return _json({});
      });
      final report = await api.recoverStaffEvents(staffId: 'barber-9', events: const []);
      expect(calls, 0);
      expect(report.summary.total, 0);
    });

    test('409 ACCOUNT_NOT_SUSPENDED is surfaced as ApiError.isAccountNotSuspended', () async {
      final api = _manager((r) async => _json({
            'error': {'code': 'ACCOUNT_NOT_SUSPENDED', 'message': 'هذا الحساب غير موقوف'}
          }, 409));
      await expectLater(
        api.recoverStaffEvents(staffId: 'barber-9', events: [_event(1)]),
        throwsA(isA<ApiError>().having((e) => e.isAccountNotSuspended, 'isAccountNotSuspended', isTrue)),
      );
    });

    test('recovered-events list and acknowledgement', () async {
      final seen = <String>[];
      final api = _manager((r) async {
        seen.add('${r.method} ${r.url.path}${r.url.hasQuery ? '?${r.url.query}' : ''}');
        if (r.method == 'POST') return _json({'ok': true});
        return _json([
          {
            'id': 'item-1',
            'staffId': 'barber-9',
            'staffName': 'خالد',
            'eventId': 'evt-1',
            'type': 'payment_confirmed',
            'bookingId': 'b1',
            'customerName': 'فهد',
            'occurredAt': '2026-09-24T09:59:00.000Z',
            'approximate': true,
            'suspendedAt': '2026-09-24T10:00:00.000Z',
            'reason': null,
            'recoveredBy': {'id': 'mgr-1', 'name': 'المدير'},
            'recoveredAt': '2026-09-24T12:00:00.000Z',
            'reviewedAt': null,
            'reviewedBy': null,
          }
        ]);
      });
      final items = await api.getRecoveredEvents();
      expect(items.single.type, 'payment_confirmed');
      expect(items.single.customerName, 'فهد');
      expect(items.single.approximate, isTrue);
      expect(items.single.recoveredByName, 'المدير');
      expect(items.single.reviewed, isFalse);
      await api.getRecoveredEvents(all: true);
      await api.acknowledgeRecoveredEvent('item-1');
      expect(seen, [
        'GET /v1/manager/recovered-events',
        'GET /v1/manager/recovered-events?status=all',
        'POST /v1/manager/recovered-events/item-1/ack',
      ]);
    });
  });

  group('Outbox — ق40', () {
    test('exportPending returns every outbox event in deviceSeq order, ignoring backoff', () async {
      final store = InMemoryLocalStore();
      final outbox = Outbox(store: store, api: _manager((r) async => _json([])));
      await outbox.add(_event(2));
      await outbox.add(_event(1));
      await store.putOutboxEntry(OutboxEntry(
        event: _event(3),
        attempts: 4,
        nextRetryAt: DateTime.now().add(const Duration(hours: 1)),
      ));
      expect((await outbox.exportPending()).map((e) => e.deviceSeq), [1, 2, 3]);
    });

    test('uploadForRecovery removes answered events; a failure keeps the outbox intact', () async {
      final store = InMemoryLocalStore();
      var fail = true;
      final outbox = Outbox(
        store: store,
        api: _manager((r) async {
          if (fail) return _json({'error': {'code': 'ACCOUNT_NOT_SUSPENDED', 'message': 'x'}}, 409);
          final events = ((jsonDecode(r.body) as Map)['events'] as List);
          // The server "forgets" to answer the last event: it must stay.
          return _json(_answer(events.take(events.length - 1).toList()));
        }),
      );
      for (var i = 1; i <= 4; i++) {
        await outbox.add(_event(i));
      }
      await expectLater(outbox.uploadForRecovery('barber-9'), throwsA(isA<ApiError>()));
      expect(await outbox.pendingCount(), 4);

      fail = false;
      final report = await outbox.uploadForRecovery('barber-9');
      expect(report.summary.applied, 2);
      expect(report.summary.rejectedAfterSuspension, 1);
      expect((await store.getOutbox()).map((e) => e.event.id), ['evt-4']);
    });

    test('StaffSyncEngine.exportPendingForRecovery stops the loop and exports the outbox', () async {
      final store = InMemoryLocalStore();
      final engine = StaffSyncEngine(api: _manager((r) async => _json([])), store: store);
      await engine.recordEvent(DeviceEventType.breakStarted, payload: {'kind': 'rest'});
      final events = await engine.exportPendingForRecovery();
      expect(events.single.type, DeviceEventType.breakStarted);
      await engine.dispose();
    });
  });
}

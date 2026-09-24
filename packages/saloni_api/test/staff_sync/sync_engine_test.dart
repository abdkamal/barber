import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saloni_api/saloni_api.dart';
import 'package:saloni_api/staff_sync.dart';
import 'package:test/test.dart';

ApiClient _clientWith(
  Future<http.Response> Function(http.Request request) handler,
) {
  final client = ApiClient(
    baseUrl: 'https://api.example.test',
    tokenStore: InMemoryTokenStore(),
    httpClient: MockClient(handler),
  );
  client.setSession(
    const Session(
      accessToken: 'a',
      refreshToken: 'r',
      role: UserRole.barber,
      salon: SalonInfo(code: 'ABC123'),
    ),
    rememberMe: false,
  );
  return client;
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

/// A tiny fake server: heartbeat/sync/events, with a switch to drop the network.
class _FakeServer {
  bool offline = false;
  final heartbeats = <Map<String, dynamic>>[];
  final pushed = <Map<String, dynamic>>[];
  int seq = 1;

  Future<http.Response> handle(http.Request r) async {
    if (offline) throw Exception('SocketException: network unreachable');
    final path = r.url.path;
    if (path.endsWith('/heartbeat')) {
      heartbeats.add(jsonDecode(r.body) as Map<String, dynamic>);
      return _json({
        'serverTime': '2026-09-24T09:00:00.000Z',
        'seq': seq,
        'workDate': '2026-09-24',
        'state': 'connected',
        'reconnected': false,
      });
    }
    if (path.endsWith('/sync/events')) {
      final events = (jsonDecode(r.body) as Map)['events'] as List;
      pushed.addAll(events.cast<Map<String, dynamic>>());
      return _json([
        for (final e in events) {'eventId': (e as Map)['id'], 'result': 'applied'}
      ]);
    }
    if (path.endsWith('/sync')) {
      return _json({
        'changes': [],
        'seq': seq,
        'hasMore': false,
        'serverTime': '2026-09-24T09:00:00.000Z',
      });
    }
    if (path.endsWith('/staff/walk-ins')) {
      return _json({
        'id': 'bk1',
        'customerId': 'walkin',
        'barberId': 'br1',
        'serviceIds': ['s1'],
        'kind': 'queue',
        'status': 'waiting',
        'originalEta': '2026-09-24T09:00:00Z',
        'source': 'barber',
        'walkIn': true,
      }, 201);
    }
    return http.Response('not found', 404);
  }
}

void main() {
  group('StaffSyncEngine — offline walk-in refusal (design.md §10)', () {
    test('refuses to create a walk-in while offline, without any network call',
        () async {
      var networkCalls = 0;
      final api = _clientWith((request) async {
        networkCalls++;
        return http.Response('', 503);
      });
      final engine = StaffSyncEngine(api: api, store: InMemoryLocalStore());

      await expectLater(
        engine.createWalkIn(name: 'أحمد', phone: '0500000000', serviceIds: ['s1']),
        throwsA(isA<ApiError>()
            .having((e) => e.code, 'code', 'OFFLINE_WALK_IN_REFUSED')
            .having((e) => e.message, 'message', contains('دون اتصال'))),
      );
      expect(networkCalls, 0);
      await engine.dispose();
    });

    test('allows walk-in creation once online', () async {
      final server = _FakeServer();
      final engine =
          StaffSyncEngine(api: _clientWith(server.handle), store: InMemoryLocalStore());
      final states = <ConnectionState>[];
      final sub = engine.connectionState.listen(states.add);
      await engine.start();
      await engine.sync();

      expect(engine.isOnline, isTrue);
      final booking = await engine.createWalkIn(
          name: 'أحمد', phone: '0500000000', serviceIds: ['s1']);
      expect(booking.walkIn, isTrue);
      expect(states.map((s) => s.status), contains(ConnectionStatus.online));

      await sub.cancel();
      await engine.dispose();
    });
  });

  group('StaffSyncEngine — connection state', () {
    test('goes offline when heartbeat/sync fails', () async {
      final api = _clientWith((request) async => http.Response('', 503));
      final engine = StaffSyncEngine(api: api, store: InMemoryLocalStore());

      await engine.start();
      await engine.sync();

      expect(engine.state.status, ConnectionStatus.offline);
      expect(engine.hasAttempted, isTrue);
      await engine.dispose();
    });

    test('recordEvent enqueues to the outbox and updates pendingCount', () async {
      final api = _clientWith((request) async => http.Response('', 503));
      final store = InMemoryLocalStore();
      final engine = StaffSyncEngine(api: api, store: store);

      await engine.recordEvent(DeviceEventType.serviceStarted, bookingId: 'b1');

      expect(await store.getOutbox(), hasLength(1));
      expect(engine.state.pendingCount, 1);
      await engine.dispose();
    });

    test('repeated successful heartbeats do not re-broadcast or move `since`', () async {
      final server = _FakeServer();
      var clock = DateTime.utc(2026, 9, 24, 9);
      final engine = StaffSyncEngine(
        api: _clientWith(server.handle),
        store: InMemoryLocalStore(),
        now: () => clock,
      );
      final states = <ConnectionState>[];
      final sub = engine.connectionState.listen(states.add);
      await engine.sync();
      await Future<void>.delayed(Duration.zero);
      final since = engine.state.since;
      final emitted = states.length;
      expect(emitted, greaterThan(0));
      for (var i = 0; i < 3; i++) {
        clock = clock.add(const Duration(seconds: 30));
        await engine.sync();
      }
      await Future<void>.delayed(Duration.zero);
      expect(engine.state.status, ConnectionStatus.online);
      expect(engine.state.since, since);
      expect(states.length, emitted, reason: 'no duplicate broadcasts');
      expect(states.map((s) => s.status), isNot(contains(ConnectionStatus.syncing)),
          reason: 'syncing only while sending outbox events');
      await sub.cancel();
      await engine.dispose();
    });

    test('offline `since` stays stable across failing heartbeats', () async {
      final server = _FakeServer();
      var clock = DateTime.utc(2026, 9, 24, 9);
      final engine = StaffSyncEngine(
        api: _clientWith(server.handle),
        store: InMemoryLocalStore(),
        now: () => clock,
      );
      await engine.sync();
      server.offline = true;
      clock = clock.add(const Duration(minutes: 1));
      await engine.sync();
      expect(engine.state.status, ConnectionStatus.offline);
      final offlineSince = engine.state.since;
      expect(offlineSince, clock);
      for (var i = 0; i < 3; i++) {
        clock = clock.add(const Duration(seconds: 30));
        await engine.sync();
      }
      expect(engine.state.since, offlineSince);
      server.offline = false;
      clock = clock.add(const Duration(seconds: 30));
      await engine.sync();
      expect(engine.state.status, ConnectionStatus.online);
      expect(engine.state.since, clock);
      await engine.dispose();
    });

    test('heartbeat reports the last deviceSeq without consuming one', () async {
      final server = _FakeServer();
      server.offline = true;
      final store = InMemoryLocalStore();
      final engine = StaffSyncEngine(api: _clientWith(server.handle), store: store);
      final e1 = await engine.recordEvent(DeviceEventType.serviceStarted, bookingId: 'b1');
      server.offline = false;
      await engine.sync();
      await engine.sync();
      final e2 = await engine.recordEvent(DeviceEventType.serviceFinished, bookingId: 'b1');
      expect(e1.deviceSeq, 1);
      expect(e2.deviceSeq, 2, reason: 'heartbeats must not consume sequence numbers');
      expect(server.heartbeats.map((h) => h['deviceSeq']), everyElement(1));
      expect(server.heartbeats.first.containsKey('queueDigest'), isFalse);
      await engine.dispose();
    });

    test('flushNow bypasses the exponential backoff', () async {
      final server = _FakeServer()..offline = true;
      final store = InMemoryLocalStore();
      final engine = StaffSyncEngine(api: _clientWith(server.handle), store: store);
      await engine.recordEvent(DeviceEventType.serviceStarted, bookingId: 'b1');
      await engine.sync(); // fails → backoff scheduled
      final entry = (await store.getOutbox()).single;
      expect(entry.nextRetryAt, isNotNull);

      server.offline = false;
      // A plain flush respects the backoff window.
      expect((await engine.outbox.flush()).sent, 0);
      final r = await engine.flushNow();
      expect(r.sent, 1);
      expect(await store.getOutbox(), isEmpty);
      expect(server.pushed.single['type'], 'service_started');
      expect(engine.state.status, ConnectionStatus.online);
      expect(engine.state.pendingCount, 0);
      await engine.dispose();
    });
  });
}

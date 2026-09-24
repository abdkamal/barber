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
      salonCode: 'ABC123',
    ),
    rememberMe: false,
  );
  return client;
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
      final api = _clientWith((request) async {
        if (request.url.path.endsWith('/heartbeat')) {
          return http.Response('{}', 200);
        }
        if (request.url.path.contains('/sync')) {
          return http.Response(
            jsonEncode({'changes': [], 'seq': 1, 'serverTime': '2026-09-24T09:00:00Z'}),
            200,
          );
        }
        if (request.url.path.endsWith('/staff/walk-ins')) {
          return http.Response(
            jsonEncode({
              'id': 'bk1',
              'customerId': 'walkin',
              'barberId': 'br1',
              'serviceIds': ['s1'],
              'kind': 'queue',
              'status': 'waiting',
              'originalEta': '2026-09-24T09:00:00Z',
              'source': 'barber',
              'walkIn': true,
            }),
            201,
          );
        }
        return http.Response('not found', 404);
      });
      final engine = StaffSyncEngine(api: api, store: InMemoryLocalStore());

      final states = <ConnectionState>[];
      final sub = engine.connectionState.listen(states.add);
      await engine.start();
      await Future<void>.delayed(Duration.zero);

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
      await Future<void>.delayed(Duration.zero);

      expect(engine.state.status, ConnectionStatus.offline);
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
  });
}

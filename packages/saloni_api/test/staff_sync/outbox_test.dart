import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saloni_api/saloni_api.dart';
import 'package:saloni_api/staff_sync.dart';
import 'package:test/test.dart';

DeviceEvent _event(int deviceSeq, {String? id}) => DeviceEvent(
      id: id ?? 'evt-$deviceSeq',
      deviceSeq: deviceSeq,
      type: DeviceEventType.serviceStarted,
      bookingId: 'b$deviceSeq',
      occurredAt: DateTime.utc(2026, 9, 24, 10, deviceSeq),
      approximate: false,
    );

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

void main() {
  group('Outbox', () {
    test('sends pending events in deviceSeq order', () async {
      final seenOrder = <int>[];
      final store = InMemoryLocalStore();
      final api = _clientWith((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final events = body['events'] as List;
        seenOrder.addAll(events.map((e) => e['deviceSeq'] as int));
        return http.Response(
          jsonEncode(events
              .map((e) => {'eventId': e['id'], 'result': 'applied'})
              .toList()),
          200,
        );
      });
      final outbox = Outbox(store: store, api: api);

      // Add out of order on purpose.
      await outbox.add(_event(3));
      await outbox.add(_event(1));
      await outbox.add(_event(2));

      final result = await outbox.flush();

      expect(seenOrder, [1, 2, 3]);
      expect(result.sent, 3);
      expect(result.remaining, 0);
    });

    test('applied and duplicate results remove the event from the outbox', () async {
      final store = InMemoryLocalStore();
      final api = _clientWith((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final events = body['events'] as List;
        return http.Response(
          jsonEncode([
            {'eventId': events[0]['id'], 'result': 'applied'},
            {'eventId': events[1]['id'], 'result': 'duplicate'},
          ]),
          200,
        );
      });
      final outbox = Outbox(store: store, api: api);
      await outbox.add(_event(1));
      await outbox.add(_event(2));

      final result = await outbox.flush();

      expect(result.sent, 2);
      expect(await store.getOutbox(), isEmpty);
    });

    test('rejected events are dropped (server logs them for the manager)', () async {
      final store = InMemoryLocalStore();
      final api = _clientWith((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final events = body['events'] as List;
        return http.Response(
          jsonEncode([
            {'eventId': events[0]['id'], 'result': 'rejected', 'reason': 'invalid_transition'}
          ]),
          200,
        );
      });
      final outbox = Outbox(store: store, api: api);
      await outbox.add(_event(1));

      final result = await outbox.flush();

      expect(result.sent, 0);
      expect(await store.getOutbox(), isEmpty);
    });

    test('duplicate event id added twice collapses to one outbox entry (dedup)', () async {
      final store = InMemoryLocalStore();
      final api = _clientWith((request) async => http.Response('[]', 200));
      final outbox = Outbox(store: store, api: api);

      await outbox.add(_event(1, id: 'same-id'));
      await outbox.add(_event(1, id: 'same-id'));

      expect(await outbox.pendingCount(), 1);
    });

    test('network failure keeps events pending and schedules a backoff retry', () async {
      var attempts = 0;
      final store = InMemoryLocalStore();
      final now = DateTime.utc(2026, 9, 24, 10, 0, 0);
      final api = _clientWith((request) async {
        attempts++;
        return http.Response('', 503);
      });
      final outbox = Outbox(store: store, api: api, now: () => now);
      await outbox.add(_event(1));

      final result = await outbox.flush();

      expect(attempts, 1);
      expect(result.succeeded, isFalse);
      expect(result.remaining, 1);
      final entries = await store.getOutbox();
      expect(entries.single.attempts, 1);
      expect(entries.single.nextRetryAt!.isAfter(now), isTrue);

      // Retrying immediately (before nextRetryAt) must not hit the network again.
      final secondFlush = await outbox.flush();
      expect(attempts, 1);
      expect(secondFlush.sent, 0);
      expect(secondFlush.remaining, 1);
    });

    test('retry succeeds once the backoff window has passed', () async {
      var attempts = 0;
      final store = InMemoryLocalStore();
      var now = DateTime.utc(2026, 9, 24, 10, 0, 0);
      final api = _clientWith((request) async {
        attempts++;
        if (attempts == 1) return http.Response('', 503);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final events = body['events'] as List;
        return http.Response(
          jsonEncode([
            {'eventId': events[0]['id'], 'result': 'applied'}
          ]),
          200,
        );
      });
      final outbox = Outbox(store: store, api: api, now: () => now);
      await outbox.add(_event(1));

      await outbox.flush();
      final entry = (await store.getOutbox()).single;
      now = entry.nextRetryAt!.add(const Duration(milliseconds: 1));

      final result = await outbox.flush();
      expect(attempts, 2);
      expect(result.sent, 1);
      expect(await store.getOutbox(), isEmpty);
    });
  });
}

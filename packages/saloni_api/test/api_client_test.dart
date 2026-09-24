import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saloni_api/saloni_api.dart';
import 'package:test/test.dart';

Session _session({String access = 'access-1', String refresh = 'refresh-1'}) =>
    Session(
      accessToken: access,
      refreshToken: refresh,
      role: UserRole.barber,
      salon: SalonInfo(code: 'ABC123'),
    );

/// `http.Response()` يفترض ترميز latin1 افتراضيًا إن لم يُحدَّد، فيفشل مع
/// النصوص العربية عند قراءة `bodyBytes`. هذه الدالة تبني ردًا بترميز UTF-8
/// صريح كما يفعل سيرفر حقيقي.
http.Response jsonResponse(Object? body, int statusCode,
        {Map<String, String>? headers}) =>
    http.Response(
      body == null ? '' : jsonEncode(body),
      statusCode,
      headers: {
        'content-type': 'application/json; charset=utf-8',
        ...?headers,
      },
    );

void main() {
  group('ApiClient', () {
    test('sends no Authorization header for public endpoints', () async {
      http.Request? seen;
      final client = ApiClient(
        baseUrl: 'https://api.example.test',
        tokenStore: InMemoryTokenStore(),
        httpClient: MockClient((request) async {
          seen = request;
          return jsonResponse({
              'code': 'ABC123',
              'name': 'صالون',
              'currency': 'SAR',
              'timezone': 'Asia/Riyadh',
            }, 200);
        }),
      );
      final profile = await client.getSalonProfile('ABC123');
      expect(profile.name, 'صالون');
      expect(seen!.headers.containsKey('Authorization'), isFalse);
    });

    test('single-flight refresh: concurrent 401s trigger exactly one refresh',
        () async {
      var refreshCalls = 0;
      var protectedCalls = 0;
      final store = InMemoryTokenStore();
      late ApiClient client;
      client = ApiClient(
        baseUrl: 'https://api.example.test',
        tokenStore: store,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            refreshCalls++;
            return jsonResponse(_session(access: 'access-2', refresh: 'refresh-2').toJson(), 200);
          }
          if (request.url.path.endsWith('/staff/today')) {
            protectedCalls++;
            final auth = request.headers['Authorization'];
            if (auth == 'Bearer access-1') {
              return jsonResponse({
                  'error': {'code': 'UNAUTHENTICATED', 'message': 'انتهت الجلسة'}
                }, 401);
            }
            return jsonResponse({
                'queue': [],
                'services': [],
                'breaks': [],
                'settings': {},
                'serverTime': '2026-09-24T09:00:00Z',
                'seq': 1,
              }, 200);
          }
          return http.Response('not found', 404);
        }),
      );
      await client.setSession(_session(), rememberMe: false);

      final results = await Future.wait([
        client.getStaffToday(),
        client.getStaffToday(),
        client.getStaffToday(),
      ]);

      expect(refreshCalls, 1, reason: 'refresh must happen exactly once (single-flight)');
      expect(protectedCalls, 6); // 3 calls x (first attempt with stale token + retry)
      expect(results.every((r) => r.seq == 1), isTrue);
    });

    test('signs out when refresh fails', () async {
      final store = InMemoryTokenStore();
      final client = ApiClient(
        baseUrl: 'https://api.example.test',
        tokenStore: store,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            return jsonResponse({
                'error': {'code': 'INVALID_REFRESH', 'message': 'انتهت صلاحية الجلسة'}
              }, 401);
          }
          return jsonResponse({
              'error': {'code': 'UNAUTHENTICATED', 'message': 'غير مصرح'}
            }, 401);
        }),
      );
      await client.setSession(_session(), rememberMe: false);

      final signedOutEvents = <void>[];
      final sub = client.onSignedOut.listen(signedOutEvents.add);

      await expectLater(client.getStaffToday(), throwsA(isA<ApiError>()));
      await Future<void>.delayed(Duration.zero);
      expect(signedOutEvents, hasLength(1));
      expect(await store.read(), isNull);
      await sub.cancel();
    });

    test('reuses the same Idempotency-Key across the 401-retry of one call',
        () async {
      final keysSeen = <String?>[];
      final client = ApiClient(
        baseUrl: 'https://api.example.test',
        tokenStore: InMemoryTokenStore(),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            return jsonResponse(_session(access: 'access-2').toJson(), 200);
          }
          if (request.url.path.endsWith('/staff/walk-ins')) {
            keysSeen.add(request.headers['Idempotency-Key']);
            if (request.headers['Authorization'] == 'Bearer access-1') {
              return jsonResponse({
                  'error': {'code': 'UNAUTHENTICATED', 'message': 'غير مصرح'}
                }, 401);
            }
            return jsonResponse({
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
        }),
      );
      await client.setSession(_session(), rememberMe: false);

      final booking = await client.createWalkIn(
        name: 'زبون',
        phone: '0500000000',
        serviceIds: ['s1'],
      );

      expect(booking.walkIn, isTrue);
      expect(keysSeen, hasLength(2));
      expect(keysSeen[0], isNotNull);
      expect(keysSeen[0], keysSeen[1],
          reason: 'the retried request must reuse the same Idempotency-Key');
    });

    test('maps 429 to ApiError with Retry-After surfaced', () async {
      final client = ApiClient(
        baseUrl: 'https://api.example.test',
        tokenStore: InMemoryTokenStore(),
        httpClient: MockClient((request) async {
          return http.Response('', 429, headers: {'retry-after': '7'});
        }),
      );
      await client.setSession(_session(), rememberMe: false);

      try {
        await client.getStaffToday();
        fail('expected ApiError');
      } on ApiError catch (e) {
        expect(e.statusCode, 429);
        expect(e.retryAfter, const Duration(seconds: 7));
      }
    });

    test('maps server error body to ApiError with Arabic message', () async {
      final client = ApiClient(
        baseUrl: 'https://api.example.test',
        tokenStore: InMemoryTokenStore(),
        httpClient: MockClient((request) async {
          return jsonResponse({
              'error': {'code': 'SLOT_UNAVAILABLE', 'message': 'الوقت غير متاح'}
            }, 409);
        }),
      );
      await client.setSession(_session(), rememberMe: false);

      try {
        await client.cancelBooking('b1');
        fail('expected ApiError');
      } on ApiError catch (e) {
        expect(e.code, 'SLOT_UNAVAILABLE');
        expect(e.message, 'الوقت غير متاح');
        expect(e.statusCode, 409);
      }
    });

    test('times out and maps to ApiError.timeout', () async {
      final client = ApiClient(
        baseUrl: 'https://api.example.test',
        tokenStore: InMemoryTokenStore(),
        timeout: const Duration(milliseconds: 20),
        httpClient: MockClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return http.Response('{}', 200);
        }),
      );
      await client.setSession(_session(), rememberMe: false);

      await expectLater(
        client.getStaffToday(),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', 'TIMEOUT')),
      );
    });

    test('throws signedOut without attempting a network call when no session',
        () async {
      final client = ApiClient(
        baseUrl: 'https://api.example.test',
        tokenStore: InMemoryTokenStore(),
        httpClient: MockClient((request) async {
          fail('should not call network without a session');
        }),
      );
      await expectLater(
        client.getStaffToday(),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', 'SIGNED_OUT')),
      );
    });
  });
}

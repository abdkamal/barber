import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saloni_api/saloni_api.dart';
import 'package:test/test.dart';

/// Phase 11 trial feedback: failures must be diagnosable — the server request
/// id travels with the error, validation details are readable, and network
/// failures are told apart.
void main() {
  ApiClient clientWith(Future<http.Response> Function(http.Request) handler) => ApiClient(
        baseUrl: 'https://api.test',
        tokenStore: InMemoryTokenStore(),
        httpClient: MockClient(handler),
      );

  test('500 carries the request id (body, else header) and its short form', () async {
    final c = clientWith((_) async => http.Response(
          '{"error":{"code":"INTERNAL","message":"حدث خطأ غير متوقع","requestId":"0f9c2a1e-7b7d-4c55-9e33-a1b2c3d4e5f6"}}',
          500,
          headers: {'content-type': 'application/json; charset=utf-8', 'x-request-id': 'other'},
        ));
    final e = await c.getSalonProfile('ABC-12').then<ApiError?>((_) => null, onError: (Object e) => e as ApiError);
    expect(e!.code, 'INTERNAL');
    expect(e.requestId, '0f9c2a1e-7b7d-4c55-9e33-a1b2c3d4e5f6');
    expect(e.shortRequestId, 'd4e5f6');
    expect(e.toString(), contains('0f9c2a1e'));
  });

  test('4xx takes the request id from X-Request-Id; a proxy page (non-JSON) keeps it too', () async {
    var n = 0;
    final c = clientWith((_) async => n++ == 0
        ? http.Response('{"error":{"code":"SALON_NOT_FOUND","message":"x"}}', 404,
            headers: {'x-request-id': 'req-123456789'})
        : http.Response('<html>502 Bad Gateway</html>', 502, headers: {'x-request-id': 'caddy-abcdef'}));
    final e1 = await c.getSalonProfile('X').then<ApiError?>((_) => null, onError: (Object e) => e as ApiError);
    expect(e1!.requestId, 'req-123456789');
    expect(e1.shortRequestId, '456789');
    final e2 = await c.getSalonProfile('X').then<ApiError?>((_) => null, onError: (Object e) => e as ApiError);
    expect(e2!.code, 'HTTP_502');
    expect(e2.statusCode, 502);
    expect(e2.requestId, 'caddy-abcdef');
  });

  test('validation details are exposed as issues (path + code)', () {
    final e = ApiError.fromJson({
      'error': {
        'code': 'VALIDATION_FAILED',
        'message': 'البيانات المدخلة غير صحيحة',
        'details': [
          {'path': 'salon.timezone', 'code': 'invalid_timezone'},
          {'path': 'owner.username', 'code': 'invalid_username'},
        ],
      }
    }, statusCode: 400);
    expect(e.validationIssues.map((i) => '$i'), ['salon.timezone:invalid_timezone', 'owner.username:invalid_username']);
    expect(ApiError.fromJson({'error': {'code': 'X'}}).validationIssues, isEmpty);
  });

  test('a malformed error body never throws a cast error', () {
    final e = ApiError.fromJson({'error': {'code': 42, 'message': null}}, statusCode: 500);
    expect(e.code, 'UNKNOWN');
    expect(e.message, isNotEmpty);
  });

  test('network failures are classified: no internet / server unreachable / timeout', () async {
    Future<ApiError> fail(Object error) async {
      final c = clientWith((_) async => throw error);
      return c.getSalonProfile('X').then<ApiError>((_) => throw StateError('no error'),
          onError: (Object e) => e as ApiError);
    }

    expect((await fail(const SocketException('Failed host lookup: api.test'))).networkFailure,
        NetworkFailure.noInternet);
    expect((await fail(http.ClientException('Connection refused', Uri.parse('https://api.test')))).networkFailure,
        NetworkFailure.serverUnreachable);
    expect(ApiError.timeout().networkFailure, NetworkFailure.timeout);
    expect(const ApiError(code: 'SLOT_UNAVAILABLE', message: 'x').networkFailure, isNull);
  });
}

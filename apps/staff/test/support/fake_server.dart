import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// سيرفر وهمي في الذاكرة يحاكي أشكال استجابة `server/` لمسارات الطاقم والمدير
/// المستخدمة في الاختبارات. يمرّ عبر `ApiClient` الحقيقي وغلاف التوافق.
class FakeServer {
  FakeServer({this.role = 'barber'});

  String role;
  bool online = true;
  int seq = 10;
  final DateTime now = DateTime.now().toUtc();

  final List<Map<String, dynamic>> services = [
    {'id': 's-hair', 'name': 'حلاقة شعر', 'baseDurationMin': 30, 'priceCents': 4000, 'active': true},
    {'id': 's-both', 'name': 'شعر ولحية', 'baseDurationMin': 45, 'priceCents': 6000, 'active': true},
    {'id': 's-beard', 'name': 'تهذيب لحية', 'baseDurationMin': 15, 'priceCents': 2500, 'active': true},
  ];

  final List<Map<String, dynamic>> queue = [];
  final List<Map<String, dynamic>> events = [];
  final List<String> requests = [];
  Map<String, dynamic> impact = const {'changes': [], 'pastClosing': []};
  List<Map<String, dynamic>> managerQueues = const [];
  List<String> closingWarnings = const [];
  Map<String, dynamic>? walkInResult;

  List<String> get eventTypes => [for (final e in events) e['type'] as String];

  Map<String, dynamic> booking({
    required String id,
    required String name,
    String status = 'waiting',
    List<String> serviceIds = const ['s-hair'],
    int position = 1,
    int etaInMin = 30,
    bool postponementUsed = false,
    bool walkIn = false,
    int? startedMinAgo,
    int durationMin = 30,
  }) {
    final b = {
      'id': id,
      'customerId': 'c-$id',
      'barberId': 'barber-1',
      'serviceIds': serviceIds,
      'kind': 'queue',
      'requestedAt': null,
      'status': status,
      'queuePosition': position,
      'originalEta': now.add(Duration(minutes: etaInMin)).toIso8601String(),
      'lastShownEta': null,
      'postponementUsed': postponementUsed,
      'actualStart': startedMinAgo == null
          ? null
          : now.subtract(Duration(minutes: startedMinAgo)).toIso8601String(),
      'actualEnd': null,
      'source': walkIn ? 'barber' : 'app',
      'walkIn': walkIn,
      'createdAt': now.toIso8601String(),
      'customerName': name,
      'customerPhone': '0500000000',
      'priceCents': 4000,
      'estimatedDurationMin': durationMin,
      'eta': now.add(Duration(minutes: etaInMin)).toIso8601String(),
      'calledAt': status == 'called' ? now.subtract(const Duration(minutes: 5)).toIso8601String() : null,
      'serveLate': false,
    };
    queue.add(b);
    return b;
  }

  Map<String, dynamic> session() => {
        'accessToken': 'access',
        'accessTokenExpiresIn': 900,
        'refreshToken': 'refresh',
        'role': role,
        'salon': {
          'code': 'RAHA-27',
          'name': 'صالون الراحة',
          'status': 'active',
          'timezone': 'Asia/Riyadh',
          'currency': 'SAR',
        },
        'account': {'id': 'barber-1', 'name': 'خالد الحربي'},
      };

  http.Client client() => MockClient(handle);

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path.replaceFirst('/v1', '');
    requests.add('${req.method} $path');
    if (!online) throw http.ClientException('offline', req.url);
    Map<String, dynamic> body() =>
        req.body.isEmpty ? const {} : jsonDecode(req.body) as Map<String, dynamic>;
    http.Response json(Object? v, [int status = 200]) => http.Response.bytes(
          utf8.encode(jsonEncode(v)),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );

    switch ('${req.method} $path') {
      case 'POST /auth/staff/login':
      case 'POST /auth/refresh':
        return json(session());
      case 'POST /auth/logout':
        return http.Response('', 204);
      case 'GET /staff/today':
        return json({
          'day': {'workDate': '2026-09-24', 'state': 'connected'},
          'queue': queue,
          'breaks': [],
          'walkInOnly': [],
          'closingWarnings': closingWarnings,
          'services': services,
          'settings': {'maxDisconnectWindowMinutes': 120, 'overrunAlertPercent': 100},
          'serverTime': DateTime.now().toUtc().toIso8601String(),
          'seq': seq,
        });
      case 'POST /sync/events':
        final list = (body()['events'] as List).cast<Map<String, dynamic>>();
        events.addAll(list);
        return json([
          for (final e in list) {'eventId': e['id'], 'result': 'applied'},
        ]);
      case 'GET /sync':
        return json({
          'changes': [],
          'seq': seq,
          'serverTime': DateTime.now().toUtc().toIso8601String(),
        });
      case 'POST /heartbeat':
        return json({'serverTime': DateTime.now().toUtc().toIso8601String(), 'seq': seq});
      case 'POST /staff/walk-ins':
        final b = body();
        final created = walkInResult ??
            booking(
              id: 'walk-${queue.length + 1}',
              name: b['name'] as String,
              walkIn: true,
              position: queue.length + 1,
              etaInMin: 120,
            );
        return json(created, 201);
      case 'POST /staff/impact':
        return json(impact);
      case 'GET /staff/payments':
        return json([]);
      case 'GET /manager/queues':
        return json(managerQueues);
      case 'GET /manager/settings':
        return json({'requireAccountApproval': false, 'maxActiveBookingsPerCustomer': 1});
      case 'GET /manager/breaks':
      case 'GET /manager/staff':
      case 'GET /manager/customers':
      case 'GET /manager/phone-disputes':
      case 'GET /manager/schedules':
      case 'GET /manager/absences':
      case 'GET /manager/catalog':
      case 'GET /manager/services':
        return json([]);
      case 'GET /manager/profile':
        return json({'name': 'صالون الراحة', 'about': null, 'socialLinks': []});
      case 'GET /manager/reports':
        return json({
          'revenue': {
            'perBarber': [
              {'staffId': 'b1', 'staffName': 'خالد', 'confirmed': 61000, 'awaiting': 6000},
            ],
            'total': {'confirmed': 124000, 'awaiting': 10000},
          },
          'visits': [
            {'staffId': 'b1', 'staffName': 'خالد', 'done': 12, 'cancelled': 1, 'noShow': 2, 'postponed': 1},
          ],
          'topServices': [
            {'name': 'حلاقة شعر', 'times': 20, 'revenue': 80000},
          ],
          'durationVsBase': [],
          'etaAccuracy': [
            {'staffId': 'b1', 'staffName': 'خالد', 'meanAbsMinutes': 7, 'samples': 12},
          ],
          'peakHours': [for (var h = 0; h < 24; h++) {'hour': h, 'count': h == 18 ? 5 : 1}],
          'pendingItems': {'unconfirmedPayments': 2, 'syncConflicts': 0, 'pendingAccounts': 1, 'phoneDisputes': 0},
        });
    }
    if (req.method == 'POST' && path.startsWith('/manager/bookings/') && path.endsWith('/transfer')) {
      return http.Response('', 204);
    }
    return json({
      'error': {'code': 'NOT_FOUND', 'message': 'غير موجود: $path'}
    }, 404);
  }
}

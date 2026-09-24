import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// سيرفر وهمي في الذاكرة يحاكي أشكال استجابة `server/` لمسارات الطاقم والمدير
/// المستخدمة في الاختبارات، عبر `ApiClient` الحقيقي.
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
  Map<String, dynamic>? registered;
  final List<Map<String, dynamic>> schedulesPut = [];
  final List<Map<String, dynamic>> servicesCreated = [];
  final List<Map<String, dynamic>> transfers = [];

  List<String> get eventTypes => [for (final e in events) e['type'] as String];

  /// حجز بالشكل الذي يرسله السيرفر (`BookingDto` + `customerPhone`) ويُضاف
  /// إلى طابور هذا الحلاق.
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
    final b = bookingJson(
      id: id,
      name: name,
      status: status,
      serviceIds: serviceIds,
      position: position,
      etaInMin: etaInMin,
      postponementUsed: postponementUsed,
      walkIn: walkIn,
      startedMinAgo: startedMinAgo,
      durationMin: durationMin,
    );
    queue.add(b);
    return b;
  }

  Map<String, dynamic> bookingJson({
    required String id,
    String barberId = 'barber-1',
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
    final svc = [
      for (final sid in serviceIds)
        for (final s in services)
          if (s['id'] == sid)
            {'id': sid, 'name': s['name'], 'priceCents': s['priceCents'], 'baseDurationMin': s['baseDurationMin']},
    ];
    return {
      'id': id,
      'customerId': 'c-$id',
      'barberId': barberId,
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
      'workDate': '2026-09-24',
      'customerName': name,
      'customerPhone': '0500000000',
      'services': svc,
      'priceCents': 4000,
      'estimatedDurationMin': durationMin,
      'eta': now.add(Duration(minutes: etaInMin)).toIso8601String(),
      'etaEnd': now.add(Duration(minutes: etaInMin + durationMin)).toIso8601String(),
      'calledAt': status == 'called' ? now.subtract(const Duration(minutes: 5)).toIso8601String() : null,
      'offerExpiresAt': null,
      'lastChangeReason': null,
      'serveLate': false,
      'needsReview': false,
    };
  }

  /// حلاق في `GET /manager/queues`.
  Map<String, dynamic> queueBarber({
    required String id,
    required String name,
    String? state = 'connected',
    bool accepting = true,
    List<Map<String, dynamic>> queue = const [],
  }) =>
      {
        'id': id,
        'name': name,
        'role': 'barber',
        'day': state == null
            ? null
            : {
                'workDate': '2026-09-24',
                'workStart': now.subtract(const Duration(hours: 3)).toIso8601String(),
                'workEnd': now.add(const Duration(hours: 8)).toIso8601String(),
                'state': state,
                'firstConnectedAt': null,
              },
        'accepting': accepting,
        'queue': queue,
      };

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
      case 'POST /salons/register':
        registered = body();
        return json({
          'salon': {'code': 'NEW-42', 'name': 'صالون جديد', 'status': 'pending_activation', 'timezone': 'Asia/Riyadh', 'currency': 'SAR'},
          'session': {
            ...session(),
            'role': 'manager',
            'salon': {'code': 'NEW-42', 'name': 'صالون جديد', 'status': 'pending_activation', 'timezone': 'Asia/Riyadh', 'currency': 'SAR'},
          },
        }, 201);
      case 'PUT /manager/schedules':
        schedulesPut.add(body());
        return json(body());
      case 'POST /manager/services':
        servicesCreated.add(body());
        return json({'id': 'new-${servicesCreated.length}', ...body()}, 201);
      case 'POST /auth/logout':
        return http.Response('', 204);
      case 'GET /staff/today':
        return json({
          'day': {
            'workDate': '2026-09-24',
            'workStart': now.subtract(const Duration(hours: 3)).toIso8601String(),
            'workEnd': now.add(const Duration(hours: 8)).toIso8601String(),
            'state': 'connected',
            'firstConnectedAt': now.subtract(const Duration(hours: 3)).toIso8601String(),
          },
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
          'hasMore': false,
          'serverTime': DateTime.now().toUtc().toIso8601String(),
        });
      case 'POST /heartbeat':
        return json({
          'serverTime': DateTime.now().toUtc().toIso8601String(),
          'seq': seq,
          'workDate': '2026-09-24',
          'state': 'connected',
          'reconnected': false,
        });
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
        return json({'serverTime': DateTime.now().toUtc().toIso8601String(), 'seq': seq, 'barbers': managerQueues});
      case 'GET /auth/session':
        final sess = session();
        final salon = registered != null
            ? {'code': 'NEW-42', 'name': 'صالون جديد', 'status': 'pending_activation', 'timezone': 'Asia/Riyadh', 'currency': 'SAR'}
            : sess['salon'];
        return json({'role': registered != null ? 'manager' : sess['role'], 'accountId': 'barber-1', 'salon': salon});
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
      final id = path.split('/')[3];
      transfers.add({'bookingId': id, ...body()});
      return json(bookingJson(id: id, name: 'زبون', barberId: body()['toBarberId'] as String));
    }
    return json({
      'error': {'code': 'NOT_FOUND', 'message': 'غير موجود: $path'}
    }, 404);
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'models/json_utils.dart';
import 'models/models.dart';
import 'token_store.dart';

/// عميل الواجهة البرمجية v1 — يغلّف `package:http` (قابل للحقن للاختبار)،
/// يضيف رأس التفويض، ويجدّد رمز الوصول تلقائيًا عند 401 (بمحاولة واحدة
/// ومتزامنة single-flight)، ويضيف `Idempotency-Key` للطلبات المغيّرة لحجز أو
/// دفعة أو زبون حاضر (api.md "قواعد عامة")، ويحوّل الأخطاء إلى [ApiError].
class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.tokenStore,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
    Uuid? uuid,
  })  : _http = httpClient ?? http.Client(),
        _uuid = uuid ?? const Uuid(),
        baseUri = Uri.parse(baseUrl.endsWith('/')
            ? '${baseUrl}v1'
            : '$baseUrl/v1');

  final http.Client _http;
  final Uuid _uuid;
  final TokenStore tokenStore;
  final Duration timeout;
  final Uri baseUri;

  Session? _session;
  bool _persistSession = false;
  Future<Session?>? _refreshInFlight;

  final StreamController<void> _signedOutController =
      StreamController<void>.broadcast();

  /// يصدر حدثًا عند تعذّر تجديد الجلسة (يجب على التطبيق تسجيل خروج المستخدم).
  Stream<void> get onSignedOut => _signedOutController.stream;

  /// يُستدعى بعد دخول ناجح لحفظ الجلسة في الذاكرة والمخزن الآمن.
  Future<void> setSession(Session session, {required bool rememberMe}) async {
    _session = session;
    _persistSession = rememberMe;
    await tokenStore.save(session, persist: rememberMe);
  }

  /// يحمّل جلسة محفوظة سابقًا (عند بدء التطبيق)، إن وُجدت.
  Future<Session?> restoreSession() async {
    final saved = await tokenStore.read();
    if (saved != null) {
      _session = saved;
      _persistSession = true;
    }
    return saved;
  }

  Future<void> logout() async {
    final session = _session;
    _session = null;
    await tokenStore.clear();
    if (session != null) {
      try {
        await _send('POST', '/auth/logout',
            body: {'refreshToken': session.refreshToken}, authRequired: false);
      } catch (_) {
        // تسجيل الخروج المحلي ينجح حتى لو تعذّر إبلاغ السيرفر.
      }
    }
  }

  void close() {
    _http.close();
    _signedOutController.close();
  }

  String newIdempotencyKey() => _uuid.v4();

  // ------------------------------------------------------------------
  // عام (بلا دخول)
  // ------------------------------------------------------------------

  Future<SalonPublicProfile> getSalonProfile(String code) async {
    final json = await _send('GET', '/salons/$code', authRequired: false);
    return SalonPublicProfile.fromJson(json as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> registerSalon(
      Map<String, dynamic> ownerAndSalon) async {
    final json = await _send('POST', '/salons/register',
        body: ownerAndSalon, authRequired: false);
    return json as Map<String, dynamic>;
  }

  // ------------------------------------------------------------------
  // الدخول
  // ------------------------------------------------------------------

  Future<Session> registerCustomer({
    required String salonCode,
    required String name,
    required String phone,
    required String password,
    bool rememberMe = false,
  }) async {
    final json = await _send('POST', '/auth/customer/register', body: {
      'salonCode': salonCode,
      'name': name,
      'phone': phone,
      'password': password,
    }, authRequired: false);
    final session = Session.fromJson(json as Map<String, dynamic>);
    await setSession(session, rememberMe: rememberMe);
    return session;
  }

  Future<Session> loginCustomer({
    required String salonCode,
    required String phone,
    required String password,
    bool rememberMe = false,
  }) async {
    final json = await _send('POST', '/auth/customer/login', body: {
      'salonCode': salonCode,
      'phone': phone,
      'password': password,
    }, authRequired: false);
    final session = Session.fromJson(json as Map<String, dynamic>);
    await setSession(session, rememberMe: rememberMe);
    return session;
  }

  Future<Session> loginStaff({
    required String salonCode,
    required String username,
    required String password,
    bool rememberMe = true,
  }) async {
    final json = await _send('POST', '/auth/staff/login', body: {
      'salonCode': salonCode,
      'username': username,
      'password': password,
    }, authRequired: false);
    final session = Session.fromJson(json as Map<String, dynamic>);
    await setSession(session, rememberMe: rememberMe);
    return session;
  }

  Future<void> requestPasswordReset({
    required String salonCode,
    required String identifier,
    required String code,
    required String newPassword,
  }) async {
    await _send('POST', '/auth/reset', body: {
      'salonCode': salonCode,
      'identifier': identifier,
      'code': code,
      'newPassword': newPassword,
    }, authRequired: false);
  }

  // ------------------------------------------------------------------
  // الزبون
  // ------------------------------------------------------------------

  Future<Map<String, dynamic>> getCustomerToday() async {
    final json = await _send('GET', '/customer/today');
    return json as Map<String, dynamic>;
  }

  Future<Quote> getQuote({
    required List<String> serviceIds,
    String? barberId,
    required BookingKind kind,
    DateTime? requestedAt,
  }) async {
    final json = await _send(
      'POST',
      '/bookings/quote',
      body: {
        'serviceIds': serviceIds,
        if (barberId != null) 'barberId': barberId,
        'kind': kind.toWire(),
        if (requestedAt != null) 'requestedAt': toIso(requestedAt),
      },
      idempotencyKey: newIdempotencyKey(),
    );
    return Quote.fromJson(json as Map<String, dynamic>);
  }

  Future<Booking> createBooking({
    List<String>? serviceIds,
    String? barberId,
    BookingKind? kind,
    DateTime? requestedAt,
    String? offerId,
    String? idempotencyKey,
  }) async {
    final json = await _send(
      'POST',
      '/bookings',
      body: offerId != null
          ? {'offerId': offerId}
          : {
              'serviceIds': serviceIds,
              if (barberId != null) 'barberId': barberId,
              'kind': kind!.toWire(),
              if (requestedAt != null) 'requestedAt': toIso(requestedAt),
            },
      idempotencyKey: idempotencyKey ?? newIdempotencyKey(),
    );
    return Booking.fromJson(json as Map<String, dynamic>);
  }

  Future<void> rejectOffer(String offerId) async {
    await _send('DELETE', '/offers/$offerId');
  }

  Future<CurrentBooking> getCurrentBooking() async {
    final json = await _send('GET', '/bookings/current');
    return CurrentBooking.fromJson(json as Map<String, dynamic>);
  }

  /// يبلّغ السيرفر بما عرضه التطبيق فعلًا — مرجع التنبيه الإلزامي (ق5).
  Future<void> markBookingSeen(String bookingId, DateTime eta) async {
    await _send('POST', '/bookings/$bookingId/seen', body: {
      'eta': toIso(eta),
    });
  }

  Future<Booking> changeBookingTime({
    required String bookingId,
    required BookingKind kind,
    DateTime? requestedAt,
    String? idempotencyKey,
  }) async {
    final json = await _send(
      'POST',
      '/bookings/$bookingId/change-time',
      body: {
        'kind': kind.toWire(),
        if (requestedAt != null) 'requestedAt': toIso(requestedAt),
      },
      idempotencyKey: idempotencyKey ?? newIdempotencyKey(),
    );
    return Booking.fromJson(json as Map<String, dynamic>);
  }

  Future<void> cancelBooking(String bookingId, {String? idempotencyKey}) async {
    await _send('POST', '/bookings/$bookingId/cancel',
        idempotencyKey: idempotencyKey ?? newIdempotencyKey());
  }

  Future<List<dynamic>> getCustomerHistory() async {
    final json = await _send('GET', '/customer/history');
    return json as List<dynamic>;
  }

  Future<void> registerDevice({
    required String fcmToken,
    required bool notificationsAllowed,
    required bool hasPlayServices,
  }) async {
    await _send('POST', '/devices', body: {
      'fcmToken': fcmToken,
      'notificationsAllowed': notificationsAllowed,
      'hasPlayServices': hasPlayServices,
    });
  }

  // ------------------------------------------------------------------
  // الطاقم (الحلاق)
  // ------------------------------------------------------------------

  Future<StaffToday> getStaffToday() async {
    final json = await _send('GET', '/staff/today');
    return StaffToday.fromJson(json as Map<String, dynamic>);
  }

  Future<List<SyncEventOutcome>> pushSyncEvents(
      List<DeviceEvent> events) async {
    final json = await _send('POST', '/sync/events', body: {
      'events': events.map((e) => e.toJson()).toList(),
    });
    final list = json as List<dynamic>;
    return list
        .map((e) => SyncEventOutcome.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<SyncPullResult> pullSync(int since) async {
    final json = await _send('GET', '/sync?since=$since');
    return SyncPullResult.fromJson(json as Map<String, dynamic>);
  }

  Future<void> heartbeat({required int deviceSeq, required String queueDigest}) async {
    await _send('POST', '/heartbeat', body: {
      'deviceSeq': deviceSeq,
      'queueDigest': queueDigest,
    });
  }

  /// إضافة زبون حاضر — متصل فقط (design.md §6). لا تُستدعى مطلقًا في وضع
  /// عدم الاتصال؛ انظر `staff_sync.dart` لتطبيق هذا الرفض.
  Future<Booking> createWalkIn({
    required String name,
    required String phone,
    required List<String> serviceIds,
    String? idempotencyKey,
  }) async {
    final json = await _send(
      'POST',
      '/staff/walk-ins',
      body: {'name': name, 'phone': phone, 'serviceIds': serviceIds},
      idempotencyKey: idempotencyKey ?? newIdempotencyKey(),
    );
    return Booking.fromJson(json as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getStaffImpact({
    required String bookingId,
    required List<String> serviceIds,
  }) async {
    final json = await _send('POST', '/staff/impact', body: {
      'bookingId': bookingId,
      'serviceIds': serviceIds,
    });
    return json as Map<String, dynamic>;
  }

  Future<List<Payment>> getStaffPayments() async {
    final json = await _send('GET', '/staff/payments');
    return (json as List<dynamic>)
        .map((e) => Payment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ------------------------------------------------------------------
  // المدير — لا نماذج مخصّصة مطلوبة؛ تمرير JSON خام (انظر README).
  // ------------------------------------------------------------------

  Future<Map<String, dynamic>> getManagerProfile() async =>
      await _send('GET', '/manager/profile') as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateManagerProfile(
          Map<String, dynamic> body) async =>
      await _send('PUT', '/manager/profile', body: body)
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> addManagerPhoto(Map<String, dynamic> body) async =>
      await _send('POST', '/manager/photos', body: body)
          as Map<String, dynamic>;

  Future<void> deleteManagerPhoto(String id) async =>
      await _send('DELETE', '/manager/photos/$id');

  Future<List<dynamic>> getManagerCatalog() async =>
      await _send('GET', '/manager/catalog') as List<dynamic>;

  Future<Map<String, dynamic>> createManagerCatalogItem(
          Map<String, dynamic> body) async =>
      await _send('POST', '/manager/catalog', body: body)
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateManagerCatalogItem(
          String id, Map<String, dynamic> body) async =>
      await _send('PUT', '/manager/catalog/$id', body: body)
          as Map<String, dynamic>;

  Future<void> deleteManagerCatalogItem(String id) async =>
      await _send('DELETE', '/manager/catalog/$id');

  Future<List<dynamic>> getManagerServices() async =>
      await _send('GET', '/manager/services') as List<dynamic>;

  Future<Map<String, dynamic>> createManagerService(
          Map<String, dynamic> body) async =>
      await _send('POST', '/manager/services', body: body)
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateManagerService(
          String id, Map<String, dynamic> body) async =>
      await _send('PUT', '/manager/services/$id', body: body)
          as Map<String, dynamic>;

  Future<void> deleteManagerService(String id) async =>
      await _send('DELETE', '/manager/services/$id');

  Future<List<dynamic>> getManagerStaff() async =>
      await _send('GET', '/manager/staff') as List<dynamic>;

  Future<Map<String, dynamic>> createManagerStaff(
          Map<String, dynamic> body) async =>
      await _send('POST', '/manager/staff', body: body)
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateManagerStaff(
          String id, Map<String, dynamic> body) async =>
      await _send('PUT', '/manager/staff/$id', body: body)
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> resetStaffCode(String id) async =>
      await _send('POST', '/manager/staff/$id/reset-code')
          as Map<String, dynamic>;

  Future<List<dynamic>> getManagerSchedules() async =>
      await _send('GET', '/manager/schedules') as List<dynamic>;

  Future<Map<String, dynamic>> upsertManagerSchedule(
          Map<String, dynamic> body) async =>
      await _send('POST', '/manager/schedules', body: body)
          as Map<String, dynamic>;

  Future<List<dynamic>> getManagerBreaks() async =>
      await _send('GET', '/manager/breaks') as List<dynamic>;

  Future<Map<String, dynamic>> upsertManagerBreak(
          Map<String, dynamic> body) async =>
      await _send('POST', '/manager/breaks', body: body)
          as Map<String, dynamic>;

  Future<List<dynamic>> getManagerAbsences() async =>
      await _send('GET', '/manager/absences') as List<dynamic>;

  Future<Map<String, dynamic>> upsertManagerAbsence(
          Map<String, dynamic> body) async =>
      await _send('POST', '/manager/absences', body: body)
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> getManagerSettings() async =>
      await _send('GET', '/manager/settings') as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateManagerSettings(
          Map<String, dynamic> body) async =>
      await _send('PUT', '/manager/settings', body: body)
          as Map<String, dynamic>;

  Future<List<dynamic>> getManagerCustomers() async =>
      await _send('GET', '/manager/customers') as List<dynamic>;

  Future<void> approveCustomer(String id) async =>
      await _send('POST', '/manager/customers/$id/approve');

  Future<void> suspendCustomer(String id) async =>
      await _send('POST', '/manager/customers/$id/suspend');

  Future<Map<String, dynamic>> resetCustomerCode(String id) async =>
      await _send('POST', '/manager/customers/$id/reset-code')
          as Map<String, dynamic>;

  Future<void> linkWalkInRecord(String customerId, String walkInId) async =>
      await _send('POST', '/manager/customers/$customerId/link-walkin',
          body: {'walkInId': walkInId});

  Future<void> resolvePhoneDispute(
          String disputeId, Map<String, dynamic> resolution) async =>
      await _send('POST', '/manager/phone-disputes/$disputeId/resolve',
          body: resolution);

  Future<List<dynamic>> getManagerQueues() async =>
      await _send('GET', '/manager/queues') as List<dynamic>;

  Future<void> transferBooking({
    required String bookingId,
    required String toBarberId,
    String? idempotencyKey,
  }) async =>
      await _send('POST', '/manager/bookings/$bookingId/transfer',
          body: {'toBarberId': toBarberId},
          idempotencyKey: idempotencyKey ?? newIdempotencyKey());

  Future<Map<String, dynamic>> getManagerReports({
    required DateTime from,
    required DateTime to,
  }) async =>
      await _send('GET',
          '/manager/reports?from=${toIso(from)}&to=${toIso(to)}')
          as Map<String, dynamic>;

  // ------------------------------------------------------------------
  // النواة
  // ------------------------------------------------------------------

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
    bool authRequired = true,
  }) async {
    Session? session = authRequired ? (_session ??= await tokenStore.read()) : _session;
    if (authRequired && session == null) {
      throw ApiError.signedOut();
    }

    Future<http.Response> attempt() => _rawSend(
          method,
          path,
          body: body,
          idempotencyKey: idempotencyKey,
          accessToken: authRequired ? session!.accessToken : null,
        );

    http.Response response;
    try {
      response = await attempt();
    } on TimeoutException {
      throw ApiError.timeout();
    } catch (e) {
      throw ApiError.network(e.toString());
    }

    if (response.statusCode == 401 && authRequired) {
      final refreshed = await _refreshSession();
      if (refreshed == null) {
        _signedOutController.add(null);
        throw ApiError.signedOut();
      }
      session = refreshed;
      try {
        response = await attempt();
      } on TimeoutException {
        throw ApiError.timeout();
      } catch (e) {
        throw ApiError.network(e.toString());
      }
    }

    return _decode(response);
  }

  Future<http.Response> _rawSend(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
    String? accessToken,
  }) {
    final fullPath = '${baseUri.path}$path';
    final qIndex = fullPath.indexOf('?');
    final uri = qIndex == -1
        ? baseUri.replace(path: fullPath)
        : baseUri.replace(
            path: fullPath.substring(0, qIndex),
            query: fullPath.substring(qIndex + 1),
          );
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
    };
    final encodedBody = body == null ? null : jsonEncode(body);
    final request = switch (method) {
      'GET' => _http.get(uri, headers: headers),
      'POST' => _http.post(uri, headers: headers, body: encodedBody),
      'PUT' => _http.put(uri, headers: headers, body: encodedBody),
      'DELETE' => _http.delete(uri, headers: headers, body: encodedBody),
      _ => throw ArgumentError('Unsupported method $method'),
    };
    return request.timeout(timeout);
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode == 429) {
      final retryAfterHeader = response.headers['retry-after'];
      final seconds = int.tryParse(retryAfterHeader ?? '') ?? 1;
      throw ApiError.rateLimited(Duration(seconds: seconds));
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiError(
        code: 'HTTP_${response.statusCode}',
        message: 'حدث خطأ غير متوقع',
        statusCode: response.statusCode,
      );
    }
    throw ApiError.fromJson(json, statusCode: response.statusCode);
  }

  /// تجديد رمز الوصول — محاولة واحدة متزامنة (single-flight): كل الطلبات
  /// المتزامنة التي تصطدم بـ 401 تنتظر نفس عملية التجديد بدل تكرارها.
  Future<Session?> _refreshSession() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<Session?> _doRefresh() async {
    final current = _session;
    if (current == null) return null;
    http.Response response;
    try {
      response = await _rawSend('POST', '/auth/refresh',
          body: {'refreshToken': current.refreshToken});
    } catch (_) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _session = null;
      await tokenStore.clear();
      return null;
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final refreshed = Session.fromJson(json);
    _session = refreshed;
    await tokenStore.save(refreshed, persist: _persistSession);
    return refreshed;
  }
}

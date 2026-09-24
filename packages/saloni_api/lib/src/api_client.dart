import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
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

  /// يصدر حدثًا عندما يرفض السيرفر تجديد الجلسة (رمز تجديد منتهٍ أو ملغى أو
  /// حساب موقوف) — يجب على التطبيق حينها إعادة المستخدم لشاشة الدخول.
  ///
  /// **لا** يصدر عند فشل الشبكة أثناء التجديد: تبقى الجلسة محفوظة ويُرمى
  /// `ApiError` قابل لإعادة المحاولة (`isNetwork`).
  Stream<void> get onSignedOut => _signedOutController.stream;

  /// الجلسة الحالية في الذاكرة (بعد الدخول أو `restoreSession`)، إن وُجدت.
  Session? get currentSession => _session;

  /// يحوّل رابط وسائط نسبيًا يعيده السيرفر (`/v1/media/{code}/{file}`) إلى
  /// رابط كامل على عنوان السيرفر. الروابط الكاملة تُعاد كما هي.
  String? resolveMediaUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final parsed = Uri.tryParse(url);
    if (parsed == null) return null;
    if (parsed.hasScheme) return url;
    return baseUri.resolveUri(Uri(path: parsed.path, query: parsed.hasQuery ? parsed.query : null)).toString();
  }

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
    final json = await _send('GET', '/salons/${Uri.encodeComponent(code)}',
        authRequired: false);
    return SalonPublicProfile.fromJson(json as Map<String, dynamic>);
  }

  /// تسجيل صالون جديد (ق37): `{salon: {name, timezone, currency, phone?,
  /// address?, about?}, owner: {name, username, password}}`. المالك يدخل
  /// كمدير مباشرة (تُحفظ الجلسة) وصالونه `pending_activation`.
  Future<SalonRegistration> registerSalon({
    required Map<String, dynamic> salon,
    required Map<String, dynamic> owner,
    bool rememberMe = true,
  }) async {
    final json = await _send('POST', '/salons/register',
        body: {'salon': salon, 'owner': owner}, authRequired: false);
    final reg = SalonRegistration.fromJson(json as Map<String, dynamic>);
    await setSession(reg.session, rememberMe: rememberMe);
    return reg;
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

  /// حالة الجلسة الحالية (`GET /auth/session`) — مثل انتهاء «بانتظار التفعيل».
  Future<SessionInfo> getSessionInfo() async {
    final json = await _send('GET', '/auth/session');
    return SessionInfo.fromJson(json as Map<String, dynamic>);
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

  Future<CustomerToday> getCustomerToday() async {
    final json = await _send('GET', '/customer/today');
    return CustomerToday.fromJson(json as Map<String, dynamic>);
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

  /// الحجز النشط، أو `null` إن لم يوجد (`{"booking": null}`؛ ويُقبل
  /// `404 NO_ACTIVE_BOOKING` من إصدارات سابقة للسيرفر).
  Future<CurrentBooking?> getCurrentBooking() async {
    final dynamic json;
    try {
      json = await _send('GET', '/bookings/current');
    } on ApiError catch (e) {
      if (e.code == 'NO_ACTIVE_BOOKING') return null;
      rethrow;
    }
    if (json is! Map<String, dynamic> || json['booking'] == null) return null;
    return CurrentBooking.fromJson(json);
  }

  /// يبلّغ السيرفر بما عرضه التطبيق فعلًا — مرجع التنبيه الإلزامي (ق5).
  Future<void> markBookingSeen(String bookingId, DateTime eta) async {
    await _send('POST', '/bookings/$bookingId/seen', body: {
      'eta': toIso(eta),
    });
  }

  /// تعديل الوقت (§5.12): نقل ذري عند الإمكان ويعيد الحجز بوقته الجديد.
  /// إن تعذّرت الساعة المطلوبة يُرمى `ApiError` (`409 SLOT_UNAVAILABLE`)
  /// ويبقى الحجز كما هو، و`error.changeTimeOffer` أقرب وقت محجوز مؤقتًا —
  /// قبوله `createBooking(offerId: …)` ورفضه `rejectOffer`.
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

  Future<Booking?> cancelBooking(String bookingId,
      {String? idempotencyKey}) async {
    final json = await _send('POST', '/bookings/$bookingId/cancel',
        idempotencyKey: idempotencyKey ?? newIdempotencyKey());
    return json is Map<String, dynamic> ? Booking.fromJson(json) : null;
  }

  Future<List<HistoryVisit>> getCustomerHistory() async {
    final json = await _send('GET', '/customer/history');
    return parseList(json, HistoryVisit.fromJson);
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
    return parseList(json, SyncEventOutcome.fromJson);
  }

  Future<SyncPullResult> pullSync(int since) async {
    final json = await _send('GET', '/sync?since=$since');
    return SyncPullResult.fromJson(json as Map<String, dynamic>);
  }

  /// نبضة كل 30 ث (design.md §4). `deviceSeq` = آخر رقم تسلسل استخدمه الجهاز
  /// (لا يُستهلك رقم جديد للنبضة).
  Future<HeartbeatResult> heartbeat({required int deviceSeq}) async {
    final json = await _send('POST', '/heartbeat', body: {
      'deviceSeq': deviceSeq,
    });
    return HeartbeatResult.fromJson(json as Map<String, dynamic>);
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

  Future<StaffImpact> getStaffImpact({
    required String bookingId,
    required List<String> serviceIds,
  }) async {
    final json = await _send('POST', '/staff/impact', body: {
      'bookingId': bookingId,
      'serviceIds': serviceIds,
    });
    return StaffImpact.fromJson(json as Map<String, dynamic>);
  }

  Future<List<Payment>> getStaffPayments() async {
    final json = await _send('GET', '/staff/payments');
    return parseList(json, Payment.fromJson);
  }

  // ------------------------------------------------------------------
  // المدير — ملف الصالون والصور
  // ------------------------------------------------------------------

  /// `{code, name, about, logo, photos[{id,url,position}], address, location,
  /// phone, whatsapp, socialLinks[{platform,url}], updatedAt}`.
  Future<Map<String, dynamic>> getManagerProfile() async =>
      await _send('GET', '/manager/profile') as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateManagerProfile(
          Map<String, dynamic> body) async =>
      await _send('PUT', '/manager/profile', body: body)
          as Map<String, dynamic>;

  /// رفع صورة للمعرض (حتى 6) — `multipart/form-data` بحقل `file`.
  Future<SalonPhotoUpload> uploadManagerPhoto({
    required List<int> bytes,
    required String filename,
    String? contentType,
  }) async {
    final json = await _send('POST', '/manager/photos',
        file: _Upload(bytes, filename, contentType));
    return SalonPhotoUpload.fromJson(json as Map<String, dynamic>);
  }

  Future<void> deleteManagerPhoto(String id) async =>
      await _send('DELETE', '/manager/photos/$id');

  /// رفع شعار الصالون ← `{logo: url, path}`.
  Future<Map<String, dynamic>> uploadManagerLogo({
    required List<int> bytes,
    required String filename,
    String? contentType,
  }) async =>
      await _send('POST', '/manager/profile/logo',
          file: _Upload(bytes, filename, contentType)) as Map<String, dynamic>;

  Future<void> deleteManagerLogo() async =>
      await _send('DELETE', '/manager/profile/logo');

  // ---- الكتالوج والخدمات ----

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

  /// صورة عنصر كتالوج ← `{photo}`.
  Future<Map<String, dynamic>> uploadManagerCatalogPhoto(
    String id, {
    required List<int> bytes,
    required String filename,
    String? contentType,
  }) async =>
      await _send('POST', '/manager/catalog/$id/photo',
          file: _Upload(bytes, filename, contentType)) as Map<String, dynamic>;

  Future<void> deleteManagerCatalogPhoto(String id) async =>
      await _send('DELETE', '/manager/catalog/$id/photo');

  /// `[{id, name, durationMinutes, price, active, position}]` — تُقرأ أيضًا عبر
  /// `Service.fromJson`.
  Future<List<dynamic>> getManagerServices() async =>
      await _send('GET', '/manager/services') as List<dynamic>;

  /// `{name, durationMinutes, price}`.
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

  // ---- الطاقم ----

  Future<List<dynamic>> getManagerStaff() async =>
      await _send('GET', '/manager/staff') as List<dynamic>;

  /// `{name, username, password, role: barber|manager}`.
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

  // ---- الدوام والاستراحات والإجازات ----

  /// `[{staffId | null, weekday (0=الأحد), opensAt, closesAt}]`.
  Future<List<dynamic>> getManagerSchedules() async =>
      await _send('GET', '/manager/schedules') as List<dynamic>;

  /// يضبط دوام يوم (`PUT /manager/schedules`). `staffId: null` = دوام الصالون
  /// الافتراضي لذلك اليوم. `weekday`: 0 = الأحد … 6 = السبت (انظر
  /// [serverWeekday]). `closesAt <= opensAt` = يعبر منتصف الليل (ق30).
  Future<Map<String, dynamic>> putManagerSchedule({
    String? staffId,
    required int weekday,
    required String opensAt,
    required String closesAt,
  }) async =>
      await _send('PUT', '/manager/schedules', body: {
        'staffId': staffId,
        'weekday': weekday,
        'opensAt': opensAt,
        'closesAt': closesAt,
      }) as Map<String, dynamic>;

  Future<void> deleteManagerSchedule(int weekday, {String? staffId}) async =>
      await _send('DELETE',
          '/manager/schedules/$weekday${staffId == null ? '' : '?staffId=$staffId'}');

  Future<List<dynamic>> getManagerBreaks() async =>
      await _send('GET', '/manager/breaks') as List<dynamic>;

  /// `{staffId | 'all', type, startTime/endTime (متكررة) أو workDate/startsAt/endsAt}`
  /// ← الاستراحات المنشأة (واحدة لكل حلاق عند `all`).
  Future<List<dynamic>> createManagerBreak(Map<String, dynamic> body) async =>
      await _send('POST', '/manager/breaks', body: body) as List<dynamic>;

  Future<void> deleteManagerBreak(String id) async =>
      await _send('DELETE', '/manager/breaks/$id');

  Future<List<dynamic>> getManagerAbsences() async =>
      await _send('GET', '/manager/absences') as List<dynamic>;

  /// `{staffId, workDate, reason?}`.
  Future<Map<String, dynamic>> createManagerAbsence(
          Map<String, dynamic> body) async =>
      await _send('POST', '/manager/absences', body: body)
          as Map<String, dynamic>;

  Future<void> deleteManagerAbsence(String id) async =>
      await _send('DELETE', '/manager/absences/$id');

  // ---- الإعدادات ----

  Future<Map<String, dynamic>> getManagerSettings() async =>
      await _send('GET', '/manager/settings') as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateManagerSettings(
          Map<String, dynamic> body) async =>
      await _send('PUT', '/manager/settings', body: body)
          as Map<String, dynamic>;

  // ---- الزبائن ----

  Future<List<dynamic>> getManagerCustomers({
    String? status,
    int? limit,
    int? offset,
  }) async {
    final query = [
      if (status != null) 'status=${Uri.encodeQueryComponent(status)}',
      if (limit != null) 'limit=$limit',
      if (offset != null) 'offset=$offset',
    ].join('&');
    return await _send(
            'GET', '/manager/customers${query.isEmpty ? '' : '?$query'}')
        as List<dynamic>;
  }

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

  /// يفك ربط (أو اقتراح ربط) سجل الحاضر بحساب الزبون (H2). يُسجَّل بالتدقيق.
  Future<void> unlinkWalkInRecord(String customerId) async =>
      await _send('POST', '/manager/customers/$customerId/unlink-walkin');

  /// إعادة إسناد رقم هاتف الزبون (H2، نزاع رقم ق20) — تُلغى جلساته الحالية
  /// وربط سجله السابق. `409 PHONE_IN_USE` إن كان الرقم لحساب آخر بالفعل.
  Future<Map<String, dynamic>> updateCustomerPhone(
          String customerId, String phone) async =>
      await _send('PUT', '/manager/customers/$customerId/phone',
          body: {'phone': phone}) as Map<String, dynamic>;

  /// يوقف الحساب ويُفرج عن رقمه (H2) ليسجّل به صاحبه الحقيقي من جديد؛ لا
  /// يُعتمد الحساب الحالي بعدها قبل إسناد رقم آخر (`409 PHONE_RELEASED`).
  Future<void> releaseCustomerPhone(String customerId) async =>
      await _send('POST', '/manager/customers/$customerId/release-phone');

  /// أرقام لها أكثر من سجل حاضر غير مربوط (ق20).
  Future<List<PhoneDispute>> getPhoneDisputes() async =>
      parseList(await _send('GET', '/manager/phone-disputes'),
          PhoneDispute.fromJson);

  /// يحل النزاع بربط سجل الحاضر المختار بحساب التطبيق صاحب الرقم.
  Future<void> resolvePhoneDispute(
          {required String accountId, required String walkInId}) async =>
      await _send('POST', '/manager/phone-disputes/$accountId/resolve',
          body: {'walkInId': walkInId});

  // ---- الطوابير والنقل (ق25) ----

  Future<ManagerQueues> getManagerQueues() async => ManagerQueues.fromJson(
      await _send('GET', '/manager/queues') as Map<String, dynamic>);

  /// نقل حجز إلى حلاق آخر ← الحجز بوقته الجديد. إن لم يتسع وقت الحلاق يُرمى
  /// `ApiError` (`409 TRANSFER_NO_SLOT`) و`error.transferAlternatives` البدائل.
  Future<Booking> transferBooking({
    required String bookingId,
    required String toBarberId,
    String? idempotencyKey,
  }) async =>
      Booking.fromJson(await _send(
          'POST', '/manager/bookings/$bookingId/transfer',
          body: {'toBarberId': toBarberId},
          idempotencyKey: idempotencyKey ?? newIdempotencyKey())
          as Map<String, dynamic>);

  // ---- التقارير (§9) ----

  /// تقارير نطاق أيام عمل (تاريخ الصالون المحلي، شاملًا الطرفين). يُرسل
  /// التاريخ فقط `YYYY-MM-DD` من مكوّنات [from]/[to] كما هي (دون تحويل منطقة).
  Future<Map<String, dynamic>> getManagerReports({
    required DateTime from,
    required DateTime to,
  }) async =>
      await _send('GET',
              '/manager/reports?from=${workDateOf(from)}&to=${workDateOf(to)}')
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
    _Upload? file,
  }) async {
    Session? session =
        authRequired ? (_session ??= await tokenStore.read()) : _session;
    if (authRequired && session == null) {
      throw ApiError.signedOut();
    }

    Future<http.Response> attempt() => _rawSend(
          method,
          path,
          body: body,
          file: file,
          idempotencyKey: idempotencyKey,
          accessToken: authRequired ? session!.accessToken : null,
        );

    var response = await _guard(attempt);

    if (response.statusCode == 401 && authRequired) {
      // يرمي ApiError قابلًا لإعادة المحاولة إن تعذّر الوصول للسيرفر.
      final refreshed = await _refreshSession();
      if (refreshed == null) {
        _signedOutController.add(null);
        throw ApiError.signedOut();
      }
      session = refreshed;
      response = await _guard(attempt);
    }

    return _decode(response);
  }

  Future<http.Response> _guard(Future<http.Response> Function() run) async {
    try {
      return await run();
    } on TimeoutException {
      throw ApiError.timeout();
    } on ApiError {
      rethrow;
    } catch (e) {
      throw ApiError.network(e.toString());
    }
  }

  Uri _uri(String path) {
    final fullPath = '${baseUri.path}$path';
    final qIndex = fullPath.indexOf('?');
    return qIndex == -1
        ? baseUri.replace(path: fullPath)
        : baseUri.replace(
            path: fullPath.substring(0, qIndex),
            query: fullPath.substring(qIndex + 1),
          );
  }

  Future<http.Response> _rawSend(
    String method,
    String path, {
    Map<String, dynamic>? body,
    _Upload? file,
    String? idempotencyKey,
    String? accessToken,
  }) async {
    final uri = _uri(path);
    final headers = <String, String>{
      'Accept': 'application/json',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
    };
    final http.BaseRequest request;
    if (file != null) {
      final multipart = http.MultipartRequest(method, uri)
        ..headers.addAll(headers)
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          file.bytes,
          filename: file.filename,
          contentType: file.mediaType,
        ));
      request = multipart;
    } else {
      final plain = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) {
        plain.headers['Content-Type'] = 'application/json; charset=utf-8';
        plain.bodyBytes = utf8.encode(jsonEncode(body));
      }
      request = plain;
    }
    final streamed = await _http.send(request).timeout(timeout);
    return http.Response.fromStream(streamed).timeout(timeout);
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode == 429) {
      final retryAfterHeader = response.headers['retry-after'];
      final seconds = int.tryParse(retryAfterHeader ?? '') ?? 1;
      throw ApiError.rateLimited(Duration(seconds: seconds));
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.bodyBytes.isEmpty) return null;
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
  ///
  /// يعيد `null` فقط عندما **يرفض** السيرفر رمز التجديد (401/403) — تُمسح
  /// الجلسة حينها. فشل الشبكة أو خطأ سيرفر مؤقت يُرمى `ApiError` وتبقى
  /// الجلسة كما هي لإعادة المحاولة لاحقًا.
  Future<Session?> _refreshSession() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<Session?> _doRefresh() async {
    final current = _session;
    if (current == null) return null;
    final response = await _guard(() => _rawSend('POST', '/auth/refresh',
        body: {'refreshToken': current.refreshToken}));
    if (response.statusCode == 401 || response.statusCode == 403) {
      _session = null;
      await tokenStore.clear();
      return null;
    }
    // 429 / 5xx: ليس رفضًا للجلسة — يُرمى خطأ قابل لإعادة المحاولة.
    final json = _decode(response) as Map<String, dynamic>;
    final refreshed = Session.fromJson(json);
    _session = refreshed;
    await tokenStore.save(refreshed, persist: _persistSession);
    return refreshed;
  }
}

class _Upload {
  _Upload(this.bytes, this.filename, this.contentType);

  final List<int> bytes;
  final String filename;
  final String? contentType;

  MediaType? get mediaType {
    final type = contentType ?? _guessType(filename);
    if (type == null) return null;
    try {
      return MediaType.parse(type);
    } catch (_) {
      return null;
    }
  }

  static String? _guessType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return null;
  }
}

/// يوم الأسبوع: Dart (`DateTime.monday`=1 … `DateTime.sunday`=7) ← السيرفر
/// (الأحد=0 … السبت=6).
int serverWeekday(int dartWeekday) => dartWeekday % 7;

/// تاريخ يوم عمل `YYYY-MM-DD` من مكوّنات [d] كما هي.
String workDateOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

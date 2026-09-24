import 'package:saloni_api/saloni_api.dart';

/// واجهة الوظائف التي يحتاجها تطبيق الزبون من الواجهة البرمجية — تفصل شاشات
/// التطبيق عن [ApiClient] الحقيقي كي يسهل استبدالها بـ«زبون وهمي» في
/// الاختبارات (`test/fakes/fake_customer_api.dart`) دون شبكة حقيقية.
abstract class CustomerApi {
  Future<SalonPublicProfile> getSalonProfile(String code);

  /// رابط كامل لصورة يعيدها السيرفر نسبيًا (`/v1/media/…`).
  String? mediaUrl(String? url);

  Future<Session> registerCustomer({
    required String salonCode,
    required String name,
    required String phone,
    required String password,
    bool rememberMe = false,
  });

  Future<Session> loginCustomer({
    required String salonCode,
    required String phone,
    required String password,
    bool rememberMe = false,
  });

  Future<void> logout();

  Future<CustomerToday> getCustomerToday();

  Future<Quote> getQuote({
    required List<String> serviceIds,
    String? barberId,
    required BookingKind kind,
    DateTime? requestedAt,
  });

  Future<Booking> createBooking({
    List<String>? serviceIds,
    String? barberId,
    BookingKind? kind,
    DateTime? requestedAt,
    String? offerId,
    String? idempotencyKey,
  });

  Future<void> rejectOffer(String offerId);

  /// الحجز النشط، أو `null` إن لم يوجد.
  Future<CurrentBooking?> getCurrentBooking();

  Future<void> markBookingSeen(String bookingId, DateTime eta);

  Future<Booking> changeBookingTime({
    required String bookingId,
    required BookingKind kind,
    DateTime? requestedAt,
    String? idempotencyKey,
  });

  Future<void> cancelBooking(String bookingId, {String? idempotencyKey});

  Future<List<HistoryVisit>> getCustomerHistory();

  Future<void> registerDevice({
    required String fcmToken,
    required bool notificationsAllowed,
    required bool hasPlayServices,
  });
}

/// تنفيذ حقيقي يفوّض إلى [ApiClient] من `saloni_api`.
class RealCustomerApi implements CustomerApi {
  RealCustomerApi(this._client);

  final ApiClient _client;

  ApiClient get client => _client;

  @override
  Future<SalonPublicProfile> getSalonProfile(String code) =>
      _client.getSalonProfile(code);

  @override
  String? mediaUrl(String? url) => _client.resolveMediaUrl(url);

  @override
  Future<Session> registerCustomer({
    required String salonCode,
    required String name,
    required String phone,
    required String password,
    bool rememberMe = false,
  }) =>
      _client.registerCustomer(
        salonCode: salonCode,
        name: name,
        phone: phone,
        password: password,
        rememberMe: rememberMe,
      );

  @override
  Future<Session> loginCustomer({
    required String salonCode,
    required String phone,
    required String password,
    bool rememberMe = false,
  }) =>
      _client.loginCustomer(
        salonCode: salonCode,
        phone: phone,
        password: password,
        rememberMe: rememberMe,
      );

  @override
  Future<void> logout() => _client.logout();

  @override
  Future<CustomerToday> getCustomerToday() => _client.getCustomerToday();

  @override
  Future<Quote> getQuote({
    required List<String> serviceIds,
    String? barberId,
    required BookingKind kind,
    DateTime? requestedAt,
  }) =>
      _client.getQuote(
        serviceIds: serviceIds,
        barberId: barberId,
        kind: kind,
        requestedAt: requestedAt,
      );

  @override
  Future<Booking> createBooking({
    List<String>? serviceIds,
    String? barberId,
    BookingKind? kind,
    DateTime? requestedAt,
    String? offerId,
    String? idempotencyKey,
  }) =>
      _client.createBooking(
        serviceIds: serviceIds,
        barberId: barberId,
        kind: kind,
        requestedAt: requestedAt,
        offerId: offerId,
        idempotencyKey: idempotencyKey,
      );

  @override
  Future<void> rejectOffer(String offerId) => _client.rejectOffer(offerId);

  @override
  Future<CurrentBooking?> getCurrentBooking() => _client.getCurrentBooking();

  @override
  Future<void> markBookingSeen(String bookingId, DateTime eta) =>
      _client.markBookingSeen(bookingId, eta);

  @override
  Future<Booking> changeBookingTime({
    required String bookingId,
    required BookingKind kind,
    DateTime? requestedAt,
    String? idempotencyKey,
  }) =>
      _client.changeBookingTime(
        bookingId: bookingId,
        kind: kind,
        requestedAt: requestedAt,
        idempotencyKey: idempotencyKey,
      );

  @override
  Future<void> cancelBooking(String bookingId, {String? idempotencyKey}) async {
    await _client.cancelBooking(bookingId, idempotencyKey: idempotencyKey);
  }

  @override
  Future<List<HistoryVisit>> getCustomerHistory() => _client.getCustomerHistory();

  @override
  Future<void> registerDevice({
    required String fcmToken,
    required bool notificationsAllowed,
    required bool hasPlayServices,
  }) =>
      _client.registerDevice(
        fcmToken: fcmToken,
        notificationsAllowed: notificationsAllowed,
        hasPlayServices: hasPlayServices,
      );
}

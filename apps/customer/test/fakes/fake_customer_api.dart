import 'package:customer/services/customer_api.dart';
import 'package:saloni_api/saloni_api.dart';

/// «زبون وهمي» يطبّق [CustomerApi] بلا شبكة حقيقية — يُستخدم في اختبارات
/// الواجهات (`flutter_test`) لمحاكاة استجابات السيرفر بشكل قابل للتحكم.
class FakeCustomerApi implements CustomerApi {
  FakeCustomerApi({
    SalonPublicProfile? profile,
    Map<String, dynamic>? today,
    CurrentBooking? currentBooking,
    List<dynamic>? history,
  })  : salonProfile = profile ?? _defaultProfile,
        customerToday = today ?? _defaultToday,
        // ignore: prefer_initializing_formals — القيمة الافتراضية `null` معلنة صراحة هنا لوضوحها.
        _currentBooking = currentBooking,
        historyItems = history ?? [];

  SalonPublicProfile salonProfile;
  Map<String, dynamic> customerToday;
  CurrentBooking? _currentBooking;
  List<dynamic> historyItems;

  /// نتيجة `getQuote` القادمة — يضبطها الاختبار قبل الاستدعاء.
  Quote? nextQuote;

  /// استثناء يُرمى بدل نتيجة عادية — لمحاكاة الأخطاء.
  Object? nextQuoteError;
  Object? nextCurrentBookingError;

  bool registerCalled = false;
  bool loginCalled = false;
  bool logoutCalled = false;
  bool cancelCalled = false;
  String? lastMarkedSeenBookingId;
  DateTime? lastMarkedSeenEta;
  final List<Map<String, dynamic>> createdBookingCalls = [];
  final List<String> rejectedOfferIds = [];
  Booking? nextBooking;
  Booking? nextChangedBooking;
  Map<String, dynamic>? lastRegisteredDevice;

  @override
  Future<SalonPublicProfile> getSalonProfile(String code) async => salonProfile;

  @override
  Future<Session> registerCustomer({
    required String salonCode,
    required String name,
    required String phone,
    required String password,
    bool rememberMe = false,
  }) async {
    registerCalled = true;
    return _fakeSession(salonCode);
  }

  @override
  Future<Session> loginCustomer({
    required String salonCode,
    required String phone,
    required String password,
    bool rememberMe = false,
  }) async {
    loginCalled = true;
    return _fakeSession(salonCode);
  }

  @override
  Future<void> logout() async {
    logoutCalled = true;
  }

  @override
  Future<Map<String, dynamic>> getCustomerToday() async => customerToday;

  @override
  Future<Quote> getQuote({
    required List<String> serviceIds,
    String? barberId,
    required BookingKind kind,
    DateTime? requestedAt,
  }) async {
    if (nextQuoteError != null) throw nextQuoteError!;
    return nextQuote!;
  }

  @override
  Future<Booking> createBooking({
    List<String>? serviceIds,
    String? barberId,
    BookingKind? kind,
    DateTime? requestedAt,
    String? offerId,
    String? idempotencyKey,
  }) async {
    createdBookingCalls.add({
      'serviceIds': serviceIds,
      'barberId': barberId,
      'kind': kind,
      'requestedAt': requestedAt,
      'offerId': offerId,
    });
    return nextBooking ?? _defaultBooking;
  }

  @override
  Future<void> rejectOffer(String offerId) async {
    rejectedOfferIds.add(offerId);
  }

  @override
  Future<CurrentBooking> getCurrentBooking() async {
    if (nextCurrentBookingError != null) throw nextCurrentBookingError!;
    final b = _currentBooking;
    if (b == null) throw const ApiError(code: 'NO_ACTIVE_BOOKING', message: 'لا يوجد حجز نشط');
    return b;
  }

  void setCurrentBooking(CurrentBooking? booking) => _currentBooking = booking;

  @override
  Future<void> markBookingSeen(String bookingId, DateTime eta) async {
    lastMarkedSeenBookingId = bookingId;
    lastMarkedSeenEta = eta;
  }

  @override
  Future<Booking> changeBookingTime({
    required String bookingId,
    required BookingKind kind,
    DateTime? requestedAt,
    String? idempotencyKey,
  }) async =>
      nextChangedBooking ?? _defaultBooking;

  @override
  Future<void> cancelBooking(String bookingId, {String? idempotencyKey}) async {
    cancelCalled = true;
  }

  @override
  Future<List<dynamic>> getCustomerHistory() async => historyItems;

  @override
  Future<void> registerDevice({
    required String fcmToken,
    required bool notificationsAllowed,
    required bool hasPlayServices,
  }) async {
    lastRegisteredDevice = {
      'fcmToken': fcmToken,
      'notificationsAllowed': notificationsAllowed,
      'hasPlayServices': hasPlayServices,
    };
  }

  Session _fakeSession(String salonCode) => Session(
        accessToken: 'access',
        refreshToken: 'refresh',
        role: UserRole.customer,
        salonCode: salonCode,
      );
}

final _defaultProfile = SalonPublicProfile(
  code: 'RAHA-27',
  name: 'صالون الراحة',
  bio: 'صالون رجالي في حي النرجس.',
  address: 'الرياض — حي النرجس',
  currency: 'ر.س',
  timezone: 'Asia/Riyadh',
  contact: const SalonContactInfo(phone: '+966110000000', whatsapp: '+966550000000'),
  catalog: [
    const CatalogItem(
      id: 'svc-1',
      type: CatalogItemType.service,
      name: 'حلاقة شعر',
      priceCents: 4000,
      order: 0,
      serviceId: 'svc-1',
    ),
    const CatalogItem(
      id: 'prod-1',
      type: CatalogItemType.product,
      name: 'واكس تصفيف',
      priceCents: 4500,
      order: 1,
    ),
  ],
  workingHours: const [
    WorkingHoursEntry(weekday: 3, openMinutes: 600, closeMinutes: 1380),
  ],
);

final _defaultToday = <String, dynamic>{
  'services': [
    {'id': 'svc-1', 'name': 'حلاقة شعر', 'baseDurationMin': 38, 'priceCents': 4000},
    {'id': 'svc-2', 'name': 'شعر ولحية', 'baseDurationMin': 45, 'priceCents': 6000},
  ],
  'barbers': [
    {
      'id': 'b-1',
      'name': 'خالد الحربي',
      'dayState': 'connected',
      'nextAvailableStart': DateTime.now().toUtc().add(const Duration(minutes: 25)).toIso8601String(),
      'queueLength': 2,
    },
    {
      'id': 'b-2',
      'name': 'سعد العمري',
      'dayState': 'absent_today',
      'nextAvailableStart': null,
      'queueLength': 0,
    },
  ],
};

final _defaultBooking = Booking(
  id: 'bk-1',
  customerId: 'c-1',
  barberId: 'b-1',
  serviceIds: const ['svc-1'],
  kind: BookingKind.queue,
  status: BookingStatus.waiting,
  originalEta: DateTime.now().toUtc().add(const Duration(minutes: 25)),
  source: BookingSource.app,
);

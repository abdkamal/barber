import 'package:customer/services/customer_api.dart';
import 'package:saloni_api/saloni_api.dart';

/// «زبون وهمي» يطبّق [CustomerApi] بلا شبكة حقيقية — يُستخدم في اختبارات
/// الواجهات (`flutter_test`) لمحاكاة استجابات السيرفر بشكل قابل للتحكم.
class FakeCustomerApi implements CustomerApi {
  FakeCustomerApi({
    SalonPublicProfile? profile,
    Map<String, dynamic>? today,
    CurrentBooking? currentBooking,
    List<HistoryVisit>? history,
  })  : salonProfile = profile ?? SalonPublicProfile.fromJson(defaultProfileJson),
        // بالشكل الذي يعيده السيرفر فعلًا (`GET /customer/today`).
        customerToday = CustomerToday.fromJson(today ?? defaultTodayJson()),
        // ignore: prefer_initializing_formals — القيمة الافتراضية `null` معلنة صراحة هنا لوضوحها.
        _currentBooking = currentBooking,
        historyItems = history ?? [];

  SalonPublicProfile salonProfile;
  CustomerToday customerToday;
  CurrentBooking? _currentBooking;
  List<HistoryVisit> historyItems;

  /// خطأ يُرمى من `changeBookingTime` (مثل `409 SLOT_UNAVAILABLE` مع عرض).
  Object? nextChangeTimeError;

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
  String? mediaUrl(String? url) => url == null ? null : 'http://test.local$url';

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
  Future<CustomerToday> getCustomerToday() async => customerToday;

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
  Future<CurrentBooking?> getCurrentBooking() async {
    if (nextCurrentBookingError != null) throw nextCurrentBookingError!;
    return _currentBooking;
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
  }) async {
    if (nextChangeTimeError != null) throw nextChangeTimeError!;
    return nextChangedBooking ?? _defaultBooking;
  }

  @override
  Future<void> cancelBooking(String bookingId, {String? idempotencyKey}) async {
    cancelCalled = true;
  }

  @override
  Future<List<HistoryVisit>> getCustomerHistory() async => historyItems;

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
        salon: SalonInfo(code: salonCode, name: 'صالون الراحة', status: 'active', currency: 'SAR'),
        account: const AccountInfo(id: 'c-1', name: 'سالم', status: 'active'),
      );
}

/// ملف الصالون العام بشكل `GET /salons/{code}`.
final defaultProfileJson = <String, dynamic>{
  'code': 'RAHA-27',
  'name': 'صالون الراحة',
  'timezone': 'Asia/Riyadh',
  'currency': 'ر.س',
  'about': 'صالون رجالي في حي النرجس.',
  'logo': null,
  'address': 'الرياض — حي النرجس',
  'location': null,
  'contact': {
    'phone': '+966110000000',
    'whatsapp': '+966550000000',
    'social': [
      {'platform': 'instagram', 'url': 'https://instagram.com/raha'}
    ],
  },
  'photos': [],
  'hours': [
    {'weekday': 3, 'opensAt': '10:00', 'closesAt': '23:00', 'crossesMidnight': false},
  ],
  'openNow': true,
  'services': [
    {'id': 'svc-1', 'name': 'حلاقة شعر', 'durationMin': 30, 'price': 4000},
  ],
  'catalog': [
    {
      'id': 'svc-1',
      'kind': 'service',
      'name': 'حلاقة شعر',
      'description': null,
      'features': [],
      'price': 4000,
      'photo': null,
      'serviceId': 'svc-1',
    },
    {
      'id': 'prod-1',
      'kind': 'product',
      'name': 'واكس تصفيف',
      'description': null,
      'features': [],
      'price': 4500,
      'photo': null,
      'serviceId': null,
    },
  ],
};

/// `GET /customer/today` بالشكل الذي يرسله السيرفر.
Map<String, dynamic> defaultTodayJson({String accountStatus = 'active'}) {
  final now = DateTime.now().toUtc();
  return {
    'serverTime': now.toIso8601String(),
    'accountStatus': accountStatus,
    'currency': 'SAR',
    'services': [
      {'id': 'svc-1', 'name': 'حلاقة شعر', 'baseDurationMin': 38, 'priceCents': 4000, 'active': true},
      {'id': 'svc-2', 'name': 'شعر ولحية', 'baseDurationMin': 45, 'priceCents': 6000, 'active': true},
    ],
    'barbers': [
      {
        'id': 'b-1',
        'name': 'خالد الحربي',
        'photoUrl': null,
        'dayState': 'connected',
        'nextAvailableStart': now.add(const Duration(minutes: 25)).toIso8601String(),
        'queueLength': 2,
        'accepting': true,
        'workStart': now.subtract(const Duration(hours: 2)).toIso8601String(),
        'workEnd': now.add(const Duration(hours: 8)).toIso8601String(),
      },
      {
        'id': 'b-2',
        'name': 'سعد العمري',
        'photoUrl': null,
        'dayState': 'absent_today',
        'nextAvailableStart': null,
        'queueLength': 0,
        'accepting': false,
        'workStart': now.subtract(const Duration(hours: 2)).toIso8601String(),
        'workEnd': now.add(const Duration(hours: 8)).toIso8601String(),
      },
    ],
  };
}

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

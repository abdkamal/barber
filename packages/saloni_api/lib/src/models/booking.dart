import 'enums.dart';
import 'json_utils.dart';

/// خدمة داخل حجز بلقطة اسمها وسعرها ومدتها وقت الحجز:
/// `{id, name, priceCents, baseDurationMin}`.
class BookingServiceLine {
  const BookingServiceLine({
    required this.id,
    required this.name,
    required this.priceCents,
    required this.baseDurationMin,
  });

  final String id;
  final String name;
  final int priceCents;
  final int baseDurationMin;

  factory BookingServiceLine.fromJson(Map<String, dynamic> json) =>
      BookingServiceLine(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        priceCents: asIntOrNull(json['priceCents']) ?? 0,
        baseDurationMin: asIntOrNull(json['baseDurationMin']) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'priceCents': priceCents,
        'baseDurationMin': baseDurationMin,
      };
}

/// حجز — design.md §2 (`bookings`) و§3 (آلة الحالات)، بالشكل المثبّت في
/// api.md («أشكال مثبّتة» → `Booking`): الحقول الأساسية + الإضافية التي
/// يرسلها السيرفر لكل التطبيقات (`customerPhone` في قوائم الطاقم فقط).
class Booking {
  const Booking({
    required this.id,
    required this.customerId,
    required this.barberId,
    required this.serviceIds,
    required this.kind,
    this.requestedAt,
    required this.status,
    this.queuePosition,
    required this.originalEta,
    this.lastShownEta,
    this.postponementUsed = false,
    this.actualStart,
    this.actualEnd,
    required this.source,
    this.walkIn = false,
    this.createdAt,
    this.workDate,
    this.customerName,
    this.customerPhone,
    this.services = const [],
    this.priceCents,
    this.estimatedDurationMin,
    this.eta,
    this.etaEnd,
    this.calledAt,
    this.offerExpiresAt,
    this.lastChangeReason,
    this.serveLate = false,
    this.needsReview = false,
  });

  final String id;
  final String customerId;
  final String barberId;
  final List<String> serviceIds;
  final BookingKind kind;

  /// الساعة المطلوبة عند `kind == requested`.
  final DateTime? requestedAt;

  final BookingStatus status;

  /// ترتيب الحجز في الطابور، إن كان بانتظار الاستدعاء.
  final int? queuePosition;

  /// الوقت المتوقع الأصلي — لا يُعاد كتابته أبدًا (ق5).
  final DateTime originalEta;

  /// آخر وقت عُرض على الزبون فعليًا (مرجع التنبيه الإلزامي، ق5).
  final DateTime? lastShownEta;

  /// هل استُخدم التأجيل المتاح مرة واحدة (ق10، ق21).
  final bool postponementUsed;

  final DateTime? actualStart;
  final DateTime? actualEnd;

  final BookingSource source;

  /// حجز زبون حاضر أدخله الحلاق مباشرة.
  final bool walkIn;

  final DateTime? createdAt;

  /// يوم العمل (تاريخ محلي للصالون `YYYY-MM-DD`، ق30).
  final String? workDate;

  final String? customerName;

  /// هاتف الزبون — في قوائم الطاقم فقط.
  final String? customerPhone;

  /// الخدمات بلقطة الاسم والسعر والمدة.
  final List<BookingServiceLine> services;

  /// مجموع أسعار الخدمات (بأصغر وحدة للعملة).
  final int? priceCents;

  /// المدة المقدّرة المتعلَّمة (ق11) بالدقائق.
  final int? estimatedDurationMin;

  /// البدء المتوقع الحالي (أو البدء الفعلي أثناء الخدمة).
  final DateTime? eta;
  final DateTime? etaEnd;

  /// وقت الاستدعاء (حالة `called`).
  final DateTime? calledAt;

  /// نهاية العرض المؤقت (حالة `offered`، ق13).
  final DateTime? offerExpiresAt;

  /// نص عربي لسبب آخر تغيير في الوقت (ق5).
  final String? lastChangeReason;

  /// قرر الحلاق خدمته بعد الإغلاق (ق24).
  final bool serveLate;

  /// يحتاج مراجعة المدير (تعارض مزامنة).
  final bool needsReview;

  /// المدة للعرض: المقدّرة، وإلا مجموع المدد الأساسية.
  int? get durationMin =>
      estimatedDurationMin ??
      (services.isEmpty
          ? null
          : services.fold<int>(0, (a, s) => a + s.baseDurationMin));

  /// أسماء الخدمات مجموعة («قص + لحية»).
  String get serviceNames => services.map((s) => s.name).join(' + ');

  bool get isActive =>
      status == BookingStatus.waiting ||
      status == BookingStatus.called ||
      status == BookingStatus.inService;

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
        id: json['id'] as String,
        customerId: json['customerId'] as String,
        barberId: json['barberId'] as String,
        serviceIds: parseStringList(json['serviceIds']),
        kind: BookingKind.fromWire(json['kind'] as String),
        requestedAt: parseUtcOrNull(json['requestedAt'] as String?),
        status: BookingStatus.fromWire(json['status'] as String),
        queuePosition: asIntOrNull(json['queuePosition']),
        originalEta: parseUtc(json['originalEta'] as String),
        lastShownEta: parseUtcOrNull(json['lastShownEta'] as String?),
        postponementUsed: json['postponementUsed'] as bool? ?? false,
        actualStart: parseUtcOrNull(json['actualStart'] as String?),
        actualEnd: parseUtcOrNull(json['actualEnd'] as String?),
        source: BookingSource.fromWire(json['source'] as String? ?? 'app'),
        walkIn: json['walkIn'] as bool? ?? false,
        createdAt: parseUtcOrNull(json['createdAt'] as String?),
        workDate: json['workDate'] as String?,
        customerName: json['customerName'] as String?,
        customerPhone: json['customerPhone'] as String?,
        services: parseList(json['services'], BookingServiceLine.fromJson),
        priceCents: asIntOrNull(json['priceCents']),
        estimatedDurationMin: asIntOrNull(json['estimatedDurationMin']),
        eta: parseUtcOrNull(json['eta'] as String?),
        etaEnd: parseUtcOrNull(json['etaEnd'] as String?),
        calledAt: parseUtcOrNull(json['calledAt'] as String?),
        offerExpiresAt: parseUtcOrNull(json['offerExpiresAt'] as String?),
        lastChangeReason: json['lastChangeReason'] as String?,
        serveLate: json['serveLate'] as bool? ?? false,
        needsReview: json['needsReview'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'customerId': customerId,
        'barberId': barberId,
        'serviceIds': serviceIds,
        'kind': kind.toWire(),
        'requestedAt': toIsoOrNull(requestedAt),
        'status': status.toWire(),
        'queuePosition': queuePosition,
        'originalEta': toIso(originalEta),
        'lastShownEta': toIsoOrNull(lastShownEta),
        'postponementUsed': postponementUsed,
        'actualStart': toIsoOrNull(actualStart),
        'actualEnd': toIsoOrNull(actualEnd),
        'source': source.toWire(),
        'walkIn': walkIn,
        'createdAt': toIsoOrNull(createdAt),
        'workDate': workDate,
        'customerName': customerName,
        if (customerPhone != null) 'customerPhone': customerPhone,
        'services': services.map((s) => s.toJson()).toList(),
        'priceCents': priceCents,
        'estimatedDurationMin': estimatedDurationMin,
        'eta': toIsoOrNull(eta),
        'etaEnd': toIsoOrNull(etaEnd),
        'calledAt': toIsoOrNull(calledAt),
        'offerExpiresAt': toIsoOrNull(offerExpiresAt),
        'lastChangeReason': lastChangeReason,
        'serveLate': serveLate,
        'needsReview': needsReview,
      };
}

import 'package:saloni_api/saloni_api.dart' as sa;

/// بيانات الصالون كما يعيدها السيرفر مع الجلسة.
class SalonMeta {
  const SalonMeta({
    required this.code,
    this.name,
    this.status,
    this.timezone,
    this.currency,
  });

  final String code;
  final String? name;

  /// `pending_activation` / `active` / `suspended`.
  final String? status;
  final String? timezone;
  final String? currency;

  bool get pendingActivation => status == 'pending_activation';

  factory SalonMeta.fromJson(Map<String, dynamic> j) => SalonMeta(
        code: (j['code'] ?? '').toString(),
        name: j['name']?.toString(),
        status: j['status']?.toString(),
        timezone: j['timezone']?.toString(),
        currency: j['currency']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'status': status,
        'timezone': timezone,
        'currency': currency,
      };
}

/// حجز في طابور الحلاق مع الحقول التي يحتاجها العرض ولا يحملها نموذج
/// `sa.Booking` (اسم الزبون، الوقت المتوقع الحالي، المدة، المبلغ...).
class QueueEntry {
  const QueueEntry({
    required this.id,
    required this.customerId,
    required this.barberId,
    required this.name,
    this.phone,
    required this.status,
    required this.serviceIds,
    required this.kind,
    this.requestedAt,
    required this.originalEta,
    required this.eta,
    required this.durationMin,
    required this.priceCents,
    this.postponementUsed = false,
    this.actualStart,
    this.actualEnd,
    this.calledAt,
    this.walkIn = false,
    this.position = 0,
    this.pastClosing = false,
    this.closingDecided = false,
    this.payment,
    this.source = sa.BookingSource.app,
    this.createdAt,
  });

  final String id;
  final String customerId;
  final String barberId;
  final String name;
  final String? phone;
  final sa.BookingStatus status;
  final List<String> serviceIds;
  final sa.BookingKind kind;
  final DateTime? requestedAt;
  final DateTime originalEta;

  /// الوقت المتوقع الحالي للبدء.
  final DateTime eta;
  final int durationMin;
  final int priceCents;
  final bool postponementUsed;
  final DateTime? actualStart;
  final DateTime? actualEnd;
  final DateTime? calledAt;
  final bool walkIn;
  final int position;

  /// متوقع بعد إغلاق الحلاق (ق24) ولم يُتخذ قرار بعد.
  final bool pastClosing;
  final bool closingDecided;
  final sa.PaymentStatus? payment;
  final sa.BookingSource source;
  final DateTime? createdAt;

  bool get isActive =>
      status == sa.BookingStatus.waiting ||
      status == sa.BookingStatus.called ||
      status == sa.BookingStatus.inService;

  bool get needsClosingDecision => pastClosing && !closingDecided && isActive;

  QueueEntry copyWith({
    sa.BookingStatus? status,
    List<String>? serviceIds,
    DateTime? eta,
    int? durationMin,
    int? priceCents,
    bool? postponementUsed,
    DateTime? actualStart,
    DateTime? actualEnd,
    DateTime? calledAt,
    int? position,
    bool? pastClosing,
    bool? closingDecided,
    sa.PaymentStatus? payment,
  }) =>
      QueueEntry(
        id: id,
        customerId: customerId,
        barberId: barberId,
        name: name,
        phone: phone,
        status: status ?? this.status,
        serviceIds: serviceIds ?? this.serviceIds,
        kind: kind,
        requestedAt: requestedAt,
        originalEta: originalEta,
        eta: eta ?? this.eta,
        durationMin: durationMin ?? this.durationMin,
        priceCents: priceCents ?? this.priceCents,
        postponementUsed: postponementUsed ?? this.postponementUsed,
        actualStart: actualStart ?? this.actualStart,
        actualEnd: actualEnd ?? this.actualEnd,
        calledAt: calledAt ?? this.calledAt,
        walkIn: walkIn,
        position: position ?? this.position,
        pastClosing: pastClosing ?? this.pastClosing,
        closingDecided: closingDecided ?? this.closingDecided,
        payment: payment ?? this.payment,
        source: source,
        createdAt: createdAt,
      );

  /// يبني الإدخال من نموذج الحزمة + JSON الخام (للحقول الإضافية).
  factory QueueEntry.from(
    sa.Booking b,
    Map<String, dynamic>? raw,
    List<sa.Service> services,
  ) {
    final r = raw ?? const <String, dynamic>{};
    final customer = r['customer'] is Map ? r['customer'] as Map : const {};
    final durFromServices = _sumDuration(b.serviceIds, services);
    final priceFromServices = _sumPrice(b.serviceIds, services);
    final payStatus = r['paymentStatus'] ?? (r['payment'] is Map ? (r['payment'] as Map)['status'] : null);
    return QueueEntry(
      id: b.id,
      customerId: b.customerId,
      barberId: b.barberId,
      name: (r['customerName'] ?? customer['name'] ?? r['name'] ?? 'زبون').toString(),
      phone: (r['customerPhone'] ?? customer['phone'] ?? r['phone'])?.toString(),
      status: b.status,
      serviceIds: b.serviceIds,
      kind: b.kind,
      requestedAt: b.requestedAt,
      originalEta: b.originalEta,
      eta: _date(r['eta'] ?? r['expectedStart']) ?? b.lastShownEta ?? b.originalEta,
      durationMin: _int(r['durationMin'] ?? r['estimatedDurationMin']) ??
          (durFromServices > 0 ? durFromServices : 30),
      priceCents: _int(r['priceCents'] ?? r['amountCents'] ?? r['price']) ??
          priceFromServices,
      postponementUsed: b.postponementUsed,
      actualStart: b.actualStart,
      actualEnd: b.actualEnd,
      calledAt: _date(r['calledAt']),
      walkIn: b.walkIn || b.source == sa.BookingSource.barber,
      position: b.queuePosition ?? 0,
      pastClosing: r['pastClosing'] == true,
      closingDecided: r['closingDecision'] != null,
      payment: payStatus is String ? _payment(payStatus) : null,
      source: b.source,
      createdAt: b.createdAt,
    );
  }

  sa.Booking toBooking() => sa.Booking(
        id: id,
        customerId: customerId,
        barberId: barberId,
        serviceIds: serviceIds,
        kind: kind,
        requestedAt: requestedAt,
        status: status,
        queuePosition: position,
        originalEta: originalEta,
        postponementUsed: postponementUsed,
        actualStart: actualStart,
        actualEnd: actualEnd,
        source: source,
        walkIn: walkIn,
        createdAt: createdAt,
      );

  /// الحقول الإضافية للحفظ المحلي بجانب `sa.Booking`.
  Map<String, dynamic> extrasJson() => {
        'customerName': name,
        'customerPhone': phone,
        'eta': eta.toUtc().toIso8601String(),
        'durationMin': durationMin,
        'priceCents': priceCents,
        'calledAt': calledAt?.toUtc().toIso8601String(),
        'pastClosing': pastClosing,
        if (closingDecided) 'closingDecision': 'local',
        if (payment != null) 'paymentStatus': payment!.toWire(),
      };
}

int _sumDuration(List<String> ids, List<sa.Service> services) {
  var t = 0;
  for (final id in ids) {
    for (final s in services) {
      if (s.id == id) t += s.baseDurationMin;
    }
  }
  return t;
}

int _sumPrice(List<String> ids, List<sa.Service> services) {
  var t = 0;
  for (final id in ids) {
    for (final s in services) {
      if (s.id == id) t += s.priceCents;
    }
  }
  return t;
}

int sumDuration(List<String> ids, List<sa.Service> services) =>
    _sumDuration(ids, services);
int sumPrice(List<String> ids, List<sa.Service> services) =>
    _sumPrice(ids, services);

String serviceNames(List<String> ids, List<sa.Service> services) {
  final names = <String>[];
  for (final id in ids) {
    for (final s in services) {
      if (s.id == id) names.add(s.name);
    }
  }
  return names.isEmpty ? 'خدمة' : names.join(' + ');
}

DateTime? _date(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toUtc() : null;

int? _int(Object? v) => v is int ? v : (v is num ? v.round() : null);

sa.PaymentStatus? _payment(String v) {
  try {
    return sa.PaymentStatus.fromWire(v);
  } catch (_) {
    return null;
  }
}

/// دفعة معروضة في شاشة الدفعات.
class PaymentView {
  const PaymentView({
    required this.bookingId,
    required this.name,
    required this.services,
    required this.amountCents,
    required this.status,
    this.at,
  });
  final String bookingId;
  final String name;
  final String services;
  final int amountCents;
  final sa.PaymentStatus status;
  final DateTime? at;
}

/// أثر تعديل الخدمة على من بعده (ق9، ق24) — من `POST /staff/impact`.
class ImpactPreview {
  const ImpactPreview({
    required this.items,
    this.newDurationMin,
    this.newPriceCents,
  });

  final List<ImpactEntry> items;
  final int? newDurationMin;
  final int? newPriceCents;

  List<ImpactEntry> get pastClosing => items.where((i) => i.pastClosing).toList();
  List<ImpactEntry> get notified => items.where((i) => i.notify).toList();

  /// تحليل متسامح لشكل الاستجابة (api.md لا يفصّله).
  factory ImpactPreview.fromJson(Object? json) {
    final list = json is List
        ? json
        : (json is Map
            ? (json['items'] ?? json['affected'] ?? json['impact'] ?? const [])
            : const []);
    final items = <ImpactEntry>[];
    for (final e in (list as List)) {
      if (e is Map) items.add(ImpactEntry.fromJson(Map<String, dynamic>.from(e)));
    }
    return ImpactPreview(
      items: items,
      newDurationMin: json is Map ? _int(json['durationMin'] ?? json['newDurationMin']) : null,
      newPriceCents: json is Map ? _int(json['priceCents'] ?? json['newPriceCents'] ?? json['amountCents']) : null,
    );
  }
}

class ImpactEntry {
  const ImpactEntry({
    required this.bookingId,
    required this.name,
    this.from,
    this.to,
    required this.deltaMin,
    required this.notify,
    required this.pastClosing,
  });
  final String bookingId;
  final String name;
  final DateTime? from;
  final DateTime? to;
  final int deltaMin;
  final bool notify;
  final bool pastClosing;

  factory ImpactEntry.fromJson(Map<String, dynamic> j) {
    final from = _date(j['from'] ?? j['oldEta'] ?? j['before']);
    final to = _date(j['to'] ?? j['newEta'] ?? j['after']);
    final delta = _int(j['deltaMin'] ?? j['delta']) ??
        (from != null && to != null ? to.difference(from).inMinutes : 0);
    return ImpactEntry(
      bookingId: (j['bookingId'] ?? j['id'] ?? '').toString(),
      name: (j['customerName'] ?? j['name'] ?? 'زبون').toString(),
      from: from,
      to: to,
      deltaMin: delta,
      notify: j['notify'] == true || delta.abs() > 30,
      pastClosing: j['pastClosing'] == true,
    );
  }
}

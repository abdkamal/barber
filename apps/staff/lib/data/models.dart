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

  factory SalonMeta.fromInfo(sa.SalonInfo i) => SalonMeta(
        code: i.code,
        name: i.name,
        status: i.status,
        timezone: i.timezone,
        currency: i.currency,
      );

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
    this.canPostpone,
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

  /// ق23: إعفاء صريح من السيرفر يسمح بتأجيل جديد رغم استخدامه — `null` إن
  /// لم يرسله السيرفر بعد، فيُترك القرار له (لا حظر محلي صارم).
  final bool? canPostpone;
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
    bool? canPostpone,
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
        canPostpone: canPostpone ?? this.canPostpone,
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

  /// يبني الإدخال من حجز السيرفر (`sa.Booking` بكل حقوله) + حالة محلية
  /// محفوظة على الجهاز ([local]: قرار الإغلاق، حالة الدفع المؤكدة محليًا…).
  factory QueueEntry.from(
    sa.Booking b,
    List<sa.Service> services, {
    Map<String, dynamic>? local,
    bool? pastClosing,
  }) {
    final r = local ?? const <String, dynamic>{};
    final durFromServices = _sumDuration(b.serviceIds, services);
    final priceFromServices = _sumPrice(b.serviceIds, services);
    final payStatus = r['paymentStatus'];
    return QueueEntry(
      id: b.id,
      customerId: b.customerId,
      barberId: b.barberId,
      name: b.customerName ?? (r['customerName'] as String?) ?? 'زبون',
      phone: b.customerPhone ?? r['customerPhone'] as String?,
      status: b.status,
      serviceIds: b.serviceIds,
      kind: b.kind,
      requestedAt: b.requestedAt,
      originalEta: b.originalEta,
      eta: b.eta ?? _date(r['eta']) ?? b.lastShownEta ?? b.originalEta,
      durationMin: b.estimatedDurationMin ??
          _int(r['durationMin']) ??
          (durFromServices > 0 ? durFromServices : (b.durationMin ?? 30)),
      priceCents: b.priceCents ?? _int(r['priceCents']) ?? priceFromServices,
      postponementUsed: b.postponementUsed,
      canPostpone: b.canPostpone,
      actualStart: b.actualStart,
      actualEnd: b.actualEnd,
      calledAt: b.calledAt ?? _date(r['calledAt']),
      walkIn: b.walkIn || b.source == sa.BookingSource.barber,
      position: b.queuePosition ?? 0,
      pastClosing: pastClosing ?? r['pastClosing'] == true,
      closingDecided: b.serveLate || r['closingDecision'] != null,
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
        canPostpone: canPostpone,
        actualStart: actualStart,
        actualEnd: actualEnd,
        source: source,
        walkIn: walkIn,
        createdAt: createdAt,
        customerName: name,
        customerPhone: phone,
        priceCents: priceCents,
        estimatedDurationMin: durationMin,
        eta: eta,
        calledAt: calledAt,
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

/// حدث رفضه السيرفر عند المزامنة (انتقال غير صالح — design.md §6.2) — يُعرض
/// للحلاق برسالة واضحة تسمّي الزبون ونوع الإجراء والسبب، بدل أن يختفي بصمت.
class RejectedEvent {
  const RejectedEvent({
    required this.eventId,
    this.type,
    this.bookingId,
    this.customerName,
    this.reason,
  });

  final String eventId;
  final sa.DeviceEventType? type;
  final String? bookingId;
  final String? customerName;
  final String? reason;

  static const _actionNames = {
    sa.DeviceEventType.serviceStarted: 'بدء الخدمة',
    sa.DeviceEventType.serviceFinished: 'إنهاء الخدمة',
    sa.DeviceEventType.servicesChanged: 'تغيير الخدمة',
    sa.DeviceEventType.paymentConfirmed: 'تأكيد الدفع',
    sa.DeviceEventType.postponed: 'التأجيل',
    sa.DeviceEventType.waited: 'الانتظار',
    sa.DeviceEventType.noShow: '«لم يحضر»',
    sa.DeviceEventType.closingDecision: 'قرار تجاوز الإغلاق',
    sa.DeviceEventType.breakStarted: 'بدء الاستراحة',
    sa.DeviceEventType.breakEnded: 'إنهاء الاستراحة',
    sa.DeviceEventType.absentToday: '«لن أعمل اليوم»',
    sa.DeviceEventType.absentCancelled: 'التراجع عن «لن أعمل اليوم»',
  };

  /// أسباب رفض معروفة بنص عربي بدل الرمز.
  static const _reasons = {
    'BARBER_ABSENT': 'أنت مسجّل «لن أعمل اليوم»',
    'ABSENCE_SET_BY_MANAGER': 'سجّل المدير غيابك اليوم؛ التراجع عنه من المدير',
    'BREAK_ALREADY_OPEN': 'لديك استراحة مفتوحة',
    'NOT_WORKING': 'لا دوام لك الآن',
  };

  /// رسالة عربية واضحة تُعرض للحلاق: ماذا رُفض ولماذا.
  String get arabicMessage {
    final action = _actionNames[type] ?? 'إجراء';
    final who = customerName == null ? '' : ' لـ$customerName';
    final why = (reason == null || reason!.isEmpty) ? '' : ' — السبب: ${_reasons[reason] ?? reason}';
    return 'رفض السيرفر $action$who$why. راجع حالة الحجز الحالية.';
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

  /// من استجابة `POST /staff/impact` (`sa.StaffImpact`): المتأثرون بالتعديل
  /// + من سيتجاوز الإغلاق دون أن يتغيّر وقته (ق24) ليُتخذ قرار بشأنه.
  factory ImpactPreview.fromImpact(sa.StaffImpact impact) {
    final items = [
      for (final c in impact.changes)
        ImpactEntry(
          bookingId: c.bookingId,
          name: c.customerName ?? 'زبون',
          from: c.before,
          to: c.after,
          deltaMin: c.deltaMin,
          notify: c.notify,
          pastClosing: c.pastClosing,
        ),
    ];
    for (final p in impact.pastClosing) {
      final idx = items.indexWhere((i) => i.bookingId == p.bookingId);
      if (idx >= 0) {
        final i = items[idx];
        items[idx] = ImpactEntry(
          bookingId: i.bookingId,
          name: i.name,
          from: i.from,
          to: i.to,
          deltaMin: i.deltaMin,
          notify: i.notify,
          pastClosing: true,
        );
      } else {
        items.add(ImpactEntry(
          bookingId: p.bookingId,
          name: p.customerName ?? 'زبون',
          to: p.end,
          deltaMin: 0,
          notify: false,
          pastClosing: true,
        ));
      }
    }
    return ImpactPreview(
      items: items,
      newDurationMin: impact.newDurationMin,
      newPriceCents: impact.newPriceCents,
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
}

import 'enums.dart';
import 'json_utils.dart';

/// حجز — design.md §2 (`bookings`) و§3 (آلة الحالات).
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

  /// آخر وقت عُرض على الزبون فعليًا (مرجع التنبيه الإلزامي، ق5) — يُحدَّث عبر
  /// `POST /bookings/{id}/seen`.
  final DateTime? lastShownEta;

  /// هل استُخدم التأجيل المتاح مرة واحدة (ق10، ق21).
  final bool postponementUsed;

  final DateTime? actualStart;
  final DateTime? actualEnd;

  final BookingSource source;

  /// حجز زبون حاضر أدخله الحلاق مباشرة.
  final bool walkIn;

  final DateTime? createdAt;

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
        id: json['id'] as String,
        customerId: json['customerId'] as String,
        barberId: json['barberId'] as String,
        serviceIds: parseStringList(json['serviceIds']),
        kind: BookingKind.fromWire(json['kind'] as String),
        requestedAt: parseUtcOrNull(json['requestedAt'] as String?),
        status: BookingStatus.fromWire(json['status'] as String),
        queuePosition: json['queuePosition'] as int?,
        originalEta: parseUtc(json['originalEta'] as String),
        lastShownEta: parseUtcOrNull(json['lastShownEta'] as String?),
        postponementUsed: json['postponementUsed'] as bool? ?? false,
        actualStart: parseUtcOrNull(json['actualStart'] as String?),
        actualEnd: parseUtcOrNull(json['actualEnd'] as String?),
        source: BookingSource.fromWire(json['source'] as String? ?? 'app'),
        walkIn: json['walkIn'] as bool? ?? false,
        createdAt: parseUtcOrNull(json['createdAt'] as String?),
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
      };
}

import 'enums.dart';
import 'json_utils.dart';

/// حدث جهاز — صندوق الأحداث لتطبيق الطاقم (design.md §6.2، api.md "أحداث
/// الجهاز"): `{id, deviceSeq, type, bookingId?, occurredAt, approximate, payload}`.
class DeviceEvent {
  const DeviceEvent({
    required this.id,
    required this.deviceSeq,
    required this.type,
    this.bookingId,
    required this.occurredAt,
    required this.approximate,
    this.payload = const {},
  });

  /// معرّف فريد (UUID v4) — يُستخدم لمنع التكرار عند السيرفر.
  final String id;

  /// رقم تسلسل متزايد لهذا الجهاز — يحدد ترتيب التطبيق عند السيرفر.
  final int deviceSeq;

  final DeviceEventType type;
  final String? bookingId;

  /// وقت الحدوث الفعلي المحسوب بالساعة الرتيبة (design.md §6.2)، وليس وقت
  /// الإرسال.
  final DateTime occurredAt;

  /// `true` إذا أُعيد تشغيل الجهاز منذ آخر مزامنة (فقدان استمرارية الساعة
  /// الرتيبة) — يُستبعد من عيّنات تعلّم المدة.
  final bool approximate;

  final Map<String, dynamic> payload;

  factory DeviceEvent.fromJson(Map<String, dynamic> json) => DeviceEvent(
        id: json['id'] as String,
        deviceSeq: json['deviceSeq'] as int,
        type: DeviceEventType.fromWire(json['type'] as String),
        bookingId: json['bookingId'] as String?,
        occurredAt: parseUtc(json['occurredAt'] as String),
        approximate: json['approximate'] as bool? ?? false,
        payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'deviceSeq': deviceSeq,
        'type': type.toWire(),
        'bookingId': bookingId,
        'occurredAt': toIso(occurredAt),
        'approximate': approximate,
        'payload': payload,
      };

  DeviceEvent copyWith({bool? approximate}) => DeviceEvent(
        id: id,
        deviceSeq: deviceSeq,
        type: type,
        bookingId: bookingId,
        occurredAt: occurredAt,
        approximate: approximate ?? this.approximate,
        payload: payload,
      );
}

/// نتيجة تطبيق حدث واحد من دفعة `POST /sync/events`.
class SyncEventOutcome {
  const SyncEventOutcome({
    required this.eventId,
    required this.result,
    this.reason,
  });

  final String eventId;
  final SyncEventResult result;
  final String? reason;

  factory SyncEventOutcome.fromJson(Map<String, dynamic> json) =>
      SyncEventOutcome(
        eventId: json['eventId'] as String,
        result: SyncEventResult.fromWire(json['result'] as String),
        reason: json['reason'] as String?,
      );
}

import 'json_utils.dart';

/// تغيير واحد من `GET /sync?since=` — أساس السحب في المزامنة (design.md §6.3،
/// جدول `changes`). الشكل الدقيق للحمولة غير مفصّل في `api.md`، فتُترك حرة
/// (`data`) مع نوع نصي (`type`) ومرجع حجز اختياري؛ هذا افتراض آمن يُذكر في
/// تقرير التسليم.
class SyncChange {
  const SyncChange({
    required this.seq,
    required this.type,
    this.bookingId,
    required this.data,
    required this.occurredAt,
  });

  /// الرقم التسلسلي المتزايد لهذا التغيير.
  final int seq;

  /// نوع التغيير كما يرسله السيرفر (مثلاً `booking_created`,
  /// `booking_cancelled`, `services_updated`, `break_added`, ...).
  final String type;

  final String? bookingId;

  /// حمولة التغيير الخام كما وردت من السيرفر.
  final Map<String, dynamic> data;

  final DateTime occurredAt;

  factory SyncChange.fromJson(Map<String, dynamic> json) => SyncChange(
        seq: json['seq'] as int,
        type: json['type'] as String,
        bookingId: json['bookingId'] as String?,
        data: Map<String, dynamic>.from(json['data'] as Map? ?? const {}),
        occurredAt: parseUtc(json['occurredAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'type': type,
        'bookingId': bookingId,
        'data': data,
        'occurredAt': toIso(occurredAt),
      };
}

/// استجابة `GET /sync?since=` كاملة: `{changes[], seq, serverTime}`.
class SyncPullResult {
  const SyncPullResult({
    required this.changes,
    required this.seq,
    required this.serverTime,
  });

  final List<SyncChange> changes;
  final int seq;
  final DateTime serverTime;

  factory SyncPullResult.fromJson(Map<String, dynamic> json) =>
      SyncPullResult(
        changes: parseList(json['changes'], SyncChange.fromJson),
        seq: json['seq'] as int,
        serverTime: parseUtc(json['serverTime'] as String),
      );
}

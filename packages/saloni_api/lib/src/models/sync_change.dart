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
        seq: asIntOrNull(json['seq']) ?? 0,
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

/// استجابة `GET /sync?since=` كاملة: `{changes[], seq, hasMore, serverTime}`.
/// عند `hasMore` يُعاد السحب من `seq` فورًا.
class SyncPullResult {
  const SyncPullResult({
    required this.changes,
    required this.seq,
    this.hasMore = false,
    required this.serverTime,
  });

  final List<SyncChange> changes;
  final int seq;
  final bool hasMore;
  final DateTime serverTime;

  factory SyncPullResult.fromJson(Map<String, dynamic> json) =>
      SyncPullResult(
        changes: parseList(json['changes'], SyncChange.fromJson),
        seq: asIntOrNull(json['seq']) ?? 0,
        hasMore: json['hasMore'] as bool? ?? false,
        serverTime: parseUtc(json['serverTime'] as String),
      );
}

/// استجابة `POST /heartbeat`: `{serverTime, seq, workDate, state, reconnected}`
/// (`workDate`/`state` فارغان خارج الدوام).
class HeartbeatResult {
  const HeartbeatResult({
    required this.serverTime,
    required this.seq,
    this.workDate,
    this.state,
    this.reconnected = false,
  });

  final DateTime serverTime;
  final int seq;
  final String? workDate;

  /// `connected` أو `absent_today`.
  final String? state;
  final bool reconnected;

  factory HeartbeatResult.fromJson(Map<String, dynamic> json) =>
      HeartbeatResult(
        serverTime: parseUtc(json['serverTime'] as String),
        seq: asIntOrNull(json['seq']) ?? 0,
        workDate: json['workDate'] as String?,
        state: json['state'] as String?,
        reconnected: json['reconnected'] as bool? ?? false,
      );
}

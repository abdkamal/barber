import 'json_utils.dart';

/// ق40 — نتيجة حدث واحد في رفع المدير لإجراءات حساب موقوف
/// (`POST /manager/staff/{id}/recover-events`).
enum RecoveryResult {
  /// طُبّق (وقع قبل الإيقاف) ويُعرض للمدير للمراجعة.
  applied,

  /// وصل من قبل (إعادة رفع) — لم يُطبّق مرتين.
  duplicate,

  /// وقع في وقت الإيقاف أو بعده — لم يُطبّق.
  rejectedAfterSuspension,

  /// غير صالح (نوع مجهول، حجز غير موجود، انتقال ترفضه آلة الحالات…).
  rejectedInvalid;

  static RecoveryResult fromWire(String value) => switch (value) {
        'applied' => RecoveryResult.applied,
        'duplicate' => RecoveryResult.duplicate,
        'rejected_after_suspension' => RecoveryResult.rejectedAfterSuspension,
        'rejected_invalid' => RecoveryResult.rejectedInvalid,
        _ => throw FormatException('Unknown RecoveryResult: $value'),
      };

  String toWire() => switch (this) {
        RecoveryResult.applied => 'applied',
        RecoveryResult.duplicate => 'duplicate',
        RecoveryResult.rejectedAfterSuspension => 'rejected_after_suspension',
        RecoveryResult.rejectedInvalid => 'rejected_invalid',
      };
}

class RecoveryOutcome {
  const RecoveryOutcome({required this.eventId, required this.result, this.reason});

  final String eventId;
  final RecoveryResult result;
  final String? reason;

  factory RecoveryOutcome.fromJson(Map<String, dynamic> json) => RecoveryOutcome(
        eventId: json['eventId'] as String,
        result: RecoveryResult.fromWire(json['result'] as String),
        reason: json['reason'] as String?,
      );
}

/// ملخص رفع الاسترداد: `{applied, duplicate, rejectedAfterSuspension, rejectedInvalid}`.
class RecoverySummary {
  const RecoverySummary({
    this.applied = 0,
    this.duplicate = 0,
    this.rejectedAfterSuspension = 0,
    this.rejectedInvalid = 0,
  });

  final int applied;
  final int duplicate;
  final int rejectedAfterSuspension;
  final int rejectedInvalid;

  int get total => applied + duplicate + rejectedAfterSuspension + rejectedInvalid;

  /// ما وصل إلى السيرفر فعلًا (طُبّق الآن أو من قبل).
  int get accepted => applied + duplicate;

  /// ما لم يُطبّق (بعد الإيقاف أو غير صالح).
  int get rejected => rejectedAfterSuspension + rejectedInvalid;

  factory RecoverySummary.fromJson(Map<String, dynamic> json) => RecoverySummary(
        applied: (json['applied'] as num?)?.toInt() ?? 0,
        duplicate: (json['duplicate'] as num?)?.toInt() ?? 0,
        rejectedAfterSuspension: (json['rejectedAfterSuspension'] as num?)?.toInt() ?? 0,
        rejectedInvalid: (json['rejectedInvalid'] as num?)?.toInt() ?? 0,
      );

  factory RecoverySummary.of(Iterable<RecoveryOutcome> results) {
    int n(RecoveryResult r) => results.where((o) => o.result == r).length;
    return RecoverySummary(
      applied: n(RecoveryResult.applied),
      duplicate: n(RecoveryResult.duplicate),
      rejectedAfterSuspension: n(RecoveryResult.rejectedAfterSuspension),
      rejectedInvalid: n(RecoveryResult.rejectedInvalid),
    );
  }
}

/// رد `POST /manager/staff/{id}/recover-events`:
/// `{staffId, suspendedAt, results[{eventId, result, reason?}], summary}`.
class RecoveryReport {
  const RecoveryReport({
    required this.staffId,
    this.suspendedAt,
    this.results = const [],
    this.summary = const RecoverySummary(),
  });

  final String staffId;
  final DateTime? suspendedAt;
  final List<RecoveryOutcome> results;
  final RecoverySummary summary;

  factory RecoveryReport.fromJson(Map<String, dynamic> json) {
    final results = parseList(json['results'], RecoveryOutcome.fromJson);
    return RecoveryReport(
      staffId: json['staffId'] as String,
      suspendedAt: parseUtcOrNull(json['suspendedAt'] as String?),
      results: results,
      summary: json['summary'] is Map
          ? RecoverySummary.fromJson(Map<String, dynamic>.from(json['summary'] as Map))
          : RecoverySummary.of(results),
    );
  }

  /// يدمج ردود عدة دفعات (حد السيرفر 200 حدث للدفعة).
  RecoveryReport merge(RecoveryReport next) {
    final all = [...results, ...next.results];
    return RecoveryReport(
      staffId: staffId,
      suspendedAt: suspendedAt ?? next.suspendedAt,
      results: all,
      summary: RecoverySummary.of(all),
    );
  }
}

/// عنصر في «إجراءات مستردة للمراجعة» (`GET /manager/recovered-events`).
class RecoveredEventItem {
  const RecoveredEventItem({
    required this.id,
    required this.staffId,
    this.staffName,
    this.eventId,
    this.type,
    this.bookingId,
    this.customerName,
    this.occurredAt,
    this.approximate = false,
    this.suspendedAt,
    this.reason,
    this.recoveredById,
    this.recoveredByName,
    this.recoveredAt,
    this.reviewedAt,
    this.reviewedByName,
  });

  final String id;
  final String staffId;
  final String? staffName;
  final String? eventId;

  /// نوع حدث الجهاز (`service_finished`، `payment_confirmed`…).
  final String? type;
  final String? bookingId;
  final String? customerName;
  final DateTime? occurredAt;
  final bool approximate;
  final DateTime? suspendedAt;
  final String? reason;
  final String? recoveredById;
  final String? recoveredByName;
  final DateTime? recoveredAt;
  final DateTime? reviewedAt;
  final String? reviewedByName;

  bool get reviewed => reviewedAt != null;

  factory RecoveredEventItem.fromJson(Map<String, dynamic> json) {
    final by = json['recoveredBy'] is Map ? Map<String, dynamic>.from(json['recoveredBy'] as Map) : null;
    final rv = json['reviewedBy'] is Map ? Map<String, dynamic>.from(json['reviewedBy'] as Map) : null;
    return RecoveredEventItem(
      id: json['id'] as String,
      staffId: json['staffId'] as String,
      staffName: json['staffName'] as String?,
      eventId: json['eventId'] as String?,
      type: json['type'] as String?,
      bookingId: json['bookingId'] as String?,
      customerName: json['customerName'] as String?,
      occurredAt: parseUtcOrNull(json['occurredAt'] as String?),
      approximate: json['approximate'] as bool? ?? false,
      suspendedAt: parseUtcOrNull(json['suspendedAt'] as String?),
      reason: json['reason'] as String?,
      recoveredById: by?['id'] as String?,
      recoveredByName: by?['name'] as String?,
      recoveredAt: parseUtcOrNull(json['recoveredAt'] as String?),
      reviewedAt: parseUtcOrNull(json['reviewedAt'] as String?),
      reviewedByName: rv?['name'] as String?,
    );
  }
}

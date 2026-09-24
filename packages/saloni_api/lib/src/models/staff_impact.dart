import 'json_utils.dart';

/// أثر تعديل خدمة على حجز واحد لاحق: `{bookingId, customerName, before, after,
/// deltaMin, pastClosing, notify}`.
class ImpactChange {
  const ImpactChange({
    required this.bookingId,
    this.customerName,
    this.before,
    this.after,
    required this.deltaMin,
    this.pastClosing = false,
    this.notify = false,
  });

  final String bookingId;
  final String? customerName;
  final DateTime? before;
  final DateTime? after;
  final int deltaMin;
  final bool pastClosing;

  /// سيُنبَّه الزبون (ق5).
  final bool notify;

  factory ImpactChange.fromJson(Map<String, dynamic> json) => ImpactChange(
        bookingId: json['bookingId'] as String,
        customerName: json['customerName'] as String?,
        before: parseUtcOrNull(json['before'] as String?),
        after: parseUtcOrNull(json['after'] as String?),
        deltaMin: asIntOrNull(json['deltaMin']) ?? 0,
        pastClosing: json['pastClosing'] as bool? ?? false,
        notify: json['notify'] as bool? ?? false,
      );
}

/// حجز سيتجاوز الإغلاق بعد التعديل: `{bookingId, customerName, end, newlyPastClosing}`.
class PastClosingEntry {
  const PastClosingEntry({
    required this.bookingId,
    this.customerName,
    this.end,
    this.newlyPastClosing = false,
  });

  final String bookingId;
  final String? customerName;
  final DateTime? end;
  final bool newlyPastClosing;

  factory PastClosingEntry.fromJson(Map<String, dynamic> json) =>
      PastClosingEntry(
        bookingId: json['bookingId'] as String,
        customerName: json['customerName'] as String?,
        end: parseUtcOrNull(json['end'] as String?),
        newlyPastClosing: json['newlyPastClosing'] as bool? ?? false,
      );
}

/// `POST /staff/impact` — معاينة أثر تعديل الخدمة (ق9، ق24).
class StaffImpact {
  const StaffImpact({
    required this.bookingId,
    this.oldDurationMin,
    this.newDurationMin,
    this.oldPriceCents,
    this.newPriceCents,
    this.changes = const [],
    this.pastClosing = const [],
    this.workEnd,
  });

  final String bookingId;
  final int? oldDurationMin;
  final int? newDurationMin;
  final int? oldPriceCents;
  final int? newPriceCents;
  final List<ImpactChange> changes;
  final List<PastClosingEntry> pastClosing;
  final DateTime? workEnd;

  factory StaffImpact.fromJson(Map<String, dynamic> json) => StaffImpact(
        bookingId: json['bookingId'] as String,
        oldDurationMin: asIntOrNull(json['oldDurationMin']),
        newDurationMin: asIntOrNull(json['newDurationMin']),
        oldPriceCents: asIntOrNull(json['oldPriceCents']),
        newPriceCents: asIntOrNull(json['newPriceCents']),
        changes: parseList(json['changes'], ImpactChange.fromJson),
        pastClosing: parseList(json['pastClosing'], PastClosingEntry.fromJson),
        workEnd: parseUtcOrNull(json['workEnd'] as String?),
      );
}

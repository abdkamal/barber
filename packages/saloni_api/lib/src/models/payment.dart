import 'enums.dart';
import 'json_utils.dart';

/// دفعة — مستقلة عن حالة الخدمة (design.md §2، §3)، بشكل `GET /staff/payments`:
/// `{id, bookingId, amountCents, status, confirmedBy, confirmedAt, barberId,
/// customerName, workDate, finishedAt, createdAt}`.
class Payment {
  const Payment({
    required this.id,
    required this.bookingId,
    required this.amountCents,
    required this.status,
    this.confirmedBy,
    this.confirmedAt,
    this.barberId,
    this.customerName,
    this.workDate,
    this.finishedAt,
    this.createdAt,
  });

  final String id;
  final String bookingId;
  final int amountCents;
  final PaymentStatus status;
  final String? confirmedBy;
  final DateTime? confirmedAt;
  final String? barberId;
  final String? customerName;
  final String? workDate;

  /// نهاية الخدمة.
  final DateTime? finishedAt;
  final DateTime? createdAt;

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        id: json['id'] as String,
        bookingId: json['bookingId'] as String,
        amountCents: asIntOrNull(json['amountCents']) ?? 0,
        status: PaymentStatus.fromWire(json['status'] as String),
        confirmedBy: json['confirmedBy'] as String?,
        confirmedAt: parseUtcOrNull(json['confirmedAt'] as String?),
        barberId: json['barberId'] as String?,
        customerName: json['customerName'] as String?,
        workDate: json['workDate'] as String?,
        finishedAt: parseUtcOrNull(json['finishedAt'] as String?),
        createdAt: parseUtcOrNull(json['createdAt'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookingId': bookingId,
        'amountCents': amountCents,
        'status': status.toWire(),
        'confirmedBy': confirmedBy,
        'confirmedAt': toIsoOrNull(confirmedAt),
        'barberId': barberId,
        'customerName': customerName,
        'workDate': workDate,
        'finishedAt': toIsoOrNull(finishedAt),
        'createdAt': toIsoOrNull(createdAt),
      };
}

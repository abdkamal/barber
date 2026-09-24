import 'enums.dart';
import 'json_utils.dart';

/// دفعة — مستقلة عن حالة الخدمة (design.md §2، §3).
class Payment {
  const Payment({
    required this.id,
    required this.bookingId,
    required this.amountCents,
    required this.status,
    this.confirmedBy,
    this.confirmedAt,
  });

  final String id;
  final String bookingId;
  final int amountCents;
  final PaymentStatus status;
  final String? confirmedBy;
  final DateTime? confirmedAt;

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        id: json['id'] as String,
        bookingId: json['bookingId'] as String,
        amountCents: json['amountCents'] as int,
        status: PaymentStatus.fromWire(json['status'] as String),
        confirmedBy: json['confirmedBy'] as String?,
        confirmedAt: parseUtcOrNull(json['confirmedAt'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookingId': bookingId,
        'amountCents': amountCents,
        'status': status.toWire(),
        'confirmedBy': confirmedBy,
        'confirmedAt': toIsoOrNull(confirmedAt),
      };
}

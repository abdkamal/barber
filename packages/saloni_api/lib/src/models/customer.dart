import 'barber.dart';
import 'booking.dart';
import 'enums.dart';
import 'json_utils.dart';
import 'service.dart';

/// `GET /customer/today`:
/// `{serverTime, accountStatus, currency, services[Service], barbers[Barber]}`.
class CustomerToday {
  const CustomerToday({
    required this.serverTime,
    required this.accountStatus,
    this.currency,
    required this.services,
    required this.barbers,
  });

  final DateTime serverTime;

  /// `active` أو `pending` (بانتظار اعتماد الصالون).
  final String accountStatus;
  final String? currency;
  final List<Service> services;
  final List<Barber> barbers;

  bool get accountPending => accountStatus == 'pending';

  factory CustomerToday.fromJson(Map<String, dynamic> json) => CustomerToday(
        serverTime: parseUtcOrNull(json['serverTime'] as String?) ??
            DateTime.now().toUtc(),
        accountStatus: json['accountStatus'] as String? ?? 'active',
        currency: json['currency'] as String?,
        services: parseList(json['services'], Service.fromJson),
        barbers: parseList(json['barbers'], Barber.fromJson),
      );

  Map<String, dynamic> toJson() => {
        'serverTime': toIso(serverTime),
        'accountStatus': accountStatus,
        'currency': currency,
        'services': services.map((s) => s.toJson()).toList(),
        'barbers': barbers.map((b) => b.toJson()).toList(),
      };
}

/// دفعة زيارة في السجل: `{status, amountCents}`.
class VisitPayment {
  const VisitPayment({required this.status, required this.amountCents});

  final PaymentStatus status;
  final int amountCents;

  factory VisitPayment.fromJson(Map<String, dynamic> json) => VisitPayment(
        status: PaymentStatus.fromWire(json['status'] as String),
        amountCents: asIntOrNull(json['amountCents']) ?? 0,
      );

  Map<String, dynamic> toJson() =>
      {'status': status.toWire(), 'amountCents': amountCents};
}

/// عنصر من `GET /customer/history`: الحجز (بالحقول نفسها) + `barberName` +
/// `payment` (أو `null` إن لم تنتهِ الخدمة).
class HistoryVisit {
  const HistoryVisit({
    required this.booking,
    required this.barberName,
    this.payment,
  });

  final Booking booking;
  final String barberName;
  final VisitPayment? payment;

  factory HistoryVisit.fromJson(Map<String, dynamic> json) => HistoryVisit(
        booking: Booking.fromJson(json),
        barberName: json['barberName'] as String? ?? '',
        payment: json['payment'] is Map
            ? VisitPayment.fromJson(asMap(json['payment']))
            : null,
      );

  Map<String, dynamic> toJson() => {
        ...booking.toJson(),
        'barberName': barberName,
        'payment': payment?.toJson(),
      };
}

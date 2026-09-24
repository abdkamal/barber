import 'booking.dart';
import 'enums.dart';
import 'json_utils.dart';

/// شريط تقدّم الطابور — بدون أرقام مباشرة للزبون (ق39)، لكن العدّاد متاح هنا
/// لتوليد النقاط في الواجهة.
class BookingProgress {
  const BookingProgress({required this.done, required this.ahead});

  /// عدد الحجوزات المنجزة قبل هذا الحجز اليوم عند نفس الحلاق (حتى 4).
  final int done;

  /// عدد من ما زال ينتظر قبل هذا الحجز.
  final int ahead;

  factory BookingProgress.fromJson(Map<String, dynamic> json) =>
      BookingProgress(
        done: asIntOrNull(json['done']) ?? 0,
        ahead: asIntOrNull(json['ahead']) ?? 0,
      );

  Map<String, dynamic> toJson() => {'done': done, 'ahead': ahead};
}

/// مرجع مختصر لحلاق: `{id, name}`.
class BarberRef {
  const BarberRef({required this.id, required this.name});

  final String id;
  final String name;

  factory BarberRef.fromJson(Map<String, dynamic> json) =>
      BarberRef(id: json['id'] as String, name: json['name'] as String? ?? '');

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// عرض الحجز النشط — `GET /bookings/current` (api.md، «أشكال مثبّتة»):
/// `{booking, eta, etaEnd, originalEta, lastChangeReason, lastChangeReasonCode,
/// status, progress, live, dayState, lastUpdateAt, barber{id,name}, serverTime}`.
/// عند عدم وجود حجز نشط يعيد السيرفر `{"booking": null}` ويعيد
/// `ApiClient.getCurrentBooking` حينها `null`.
class CurrentBooking {
  const CurrentBooking({
    required this.booking,
    required this.eta,
    this.etaEnd,
    required this.originalEta,
    this.lastChangeReason,
    this.lastChangeReasonCode,
    BookingStatus? status,
    required this.progress,
    required this.live,
    this.dayState,
    required this.lastUpdateAt,
    this.barber,
    this.serverTime,
  }) : _status = status;

  final Booking booking;

  /// الوقت المتوقع الحالي (قد يختلف عن `originalEta` بعد تغييرات الطابور).
  final DateTime eta;
  final DateTime? etaEnd;

  final DateTime originalEta;

  /// سبب آخر تغيير في الوقت (نص عربي يُعرض عند التنبيه الإلزامي — ق5).
  final String? lastChangeReason;

  /// رمز السبب الثابت (مثل `transferred`).
  final String? lastChangeReasonCode;

  final BookingStatus? _status;

  /// حالة الحجز (نفس `booking.status` افتراضيًا).
  BookingStatus get status => _status ?? booking.status;

  final BookingProgress progress;

  /// هل التقدير لحظي (الحلاق متصل) أم مجمَّد بسبب انقطاع (design.md §4).
  final bool live;

  /// حالة يوم الحلاق.
  final BarberDayState? dayState;

  final DateTime lastUpdateAt;

  final BarberRef? barber;
  final DateTime? serverTime;

  factory CurrentBooking.fromJson(Map<String, dynamic> json) =>
      CurrentBooking(
        booking: Booking.fromJson(json['booking'] as Map<String, dynamic>),
        eta: parseUtc(json['eta'] as String),
        etaEnd: parseUtcOrNull(json['etaEnd'] as String?),
        originalEta: parseUtc(json['originalEta'] as String),
        lastChangeReason: json['lastChangeReason'] as String?,
        lastChangeReasonCode: json['lastChangeReasonCode'] as String?,
        status: json['status'] is String
            ? BookingStatus.fromWire(json['status'] as String)
            : null,
        progress: BookingProgress.fromJson(asMap(json['progress'])),
        live: json['live'] as bool? ?? false,
        dayState: json['dayState'] is String
            ? BarberDayState.fromWire(json['dayState'] as String)
            : null,
        lastUpdateAt: parseUtc(json['lastUpdateAt'] as String),
        barber: json['barber'] is Map
            ? BarberRef.fromJson(asMap(json['barber']))
            : null,
        serverTime: parseUtcOrNull(json['serverTime'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'booking': booking.toJson(),
        'eta': toIso(eta),
        'etaEnd': toIsoOrNull(etaEnd),
        'originalEta': toIso(originalEta),
        'lastChangeReason': lastChangeReason,
        'lastChangeReasonCode': lastChangeReasonCode,
        'status': status.toWire(),
        'progress': progress.toJson(),
        'live': live,
        'dayState': dayState?.toWire(),
        'lastUpdateAt': toIso(lastUpdateAt),
        'barber': barber?.toJson(),
        'serverTime': toIsoOrNull(serverTime),
      };
}

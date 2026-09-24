import 'booking.dart';
import 'json_utils.dart';

/// شريط تقدّم الطابور — بدون أرقام مباشرة للزبون (ق39)، لكن العدّاد متاح هنا
/// لتوليد النقاط في الواجهة.
class BookingProgress {
  const BookingProgress({required this.done, required this.ahead});

  /// عدد الحجوزات المنجزة قبل هذا الحجز اليوم عند نفس الحلاق.
  final int done;

  /// عدد من ما زال ينتظر قبل هذا الحجز.
  final int ahead;

  factory BookingProgress.fromJson(Map<String, dynamic> json) =>
      BookingProgress(
        done: json['done'] as int,
        ahead: json['ahead'] as int,
      );

  Map<String, dynamic> toJson() => {'done': done, 'ahead': ahead};
}

/// عرض الحجز النشط — `GET /bookings/current`:
/// `{booking, eta, originalEta, lastChangeReason, status, progress, live, lastUpdateAt}`.
class CurrentBooking {
  const CurrentBooking({
    required this.booking,
    required this.eta,
    required this.originalEta,
    this.lastChangeReason,
    required this.progress,
    required this.live,
    required this.lastUpdateAt,
  });

  final Booking booking;

  /// الوقت المتوقع الحالي (قد يختلف عن `originalEta` بعد تغييرات الطابور).
  final DateTime eta;

  final DateTime originalEta;

  /// سبب آخر تغيير في الوقت (يُعرض عند التنبيه الإلزامي — ق5).
  final String? lastChangeReason;

  final BookingProgress progress;

  /// هل التقدير لحظي (الحلاق متصل) أم مجمَّد بسبب انقطاع (design.md §4).
  final bool live;

  final DateTime lastUpdateAt;

  factory CurrentBooking.fromJson(Map<String, dynamic> json) =>
      CurrentBooking(
        booking: Booking.fromJson(json['booking'] as Map<String, dynamic>),
        eta: parseUtc(json['eta'] as String),
        originalEta: parseUtc(json['originalEta'] as String),
        lastChangeReason: json['lastChangeReason'] as String?,
        progress:
            BookingProgress.fromJson(json['progress'] as Map<String, dynamic>),
        live: json['live'] as bool,
        lastUpdateAt: parseUtc(json['lastUpdateAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'booking': booking.toJson(),
        'eta': toIso(eta),
        'originalEta': toIso(originalEta),
        'lastChangeReason': lastChangeReason,
        'progress': progress.toJson(),
        'live': live,
        'lastUpdateAt': toIso(lastUpdateAt),
      };
}

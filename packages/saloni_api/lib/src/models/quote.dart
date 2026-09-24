import 'enums.dart';
import 'json_utils.dart';

/// نتيجة `POST /bookings/quote` — إما قبول فوري أو عرض وقت واحد (ق13).
class Quote {
  const Quote({
    required this.barberId,
    this.barberName,
    required this.start,
    required this.end,
    required this.durationMin,
    required this.priceCents,
    required this.outcome,
    this.offerId,
    this.offerExpiresAt,
  });

  final String barberId;

  /// اسم الحلاق المختار (مفيد عند «الأسرع»).
  final String? barberName;
  final DateTime start;
  final DateTime end;
  final int durationMin;
  final int priceCents;
  final QuoteOutcome outcome;

  /// معرّف العرض عند `outcome == offer`؛ يُستخدم في `POST /bookings` أو
  /// `DELETE /offers/{id}`.
  final String? offerId;

  /// ينتهي العرض ويحرَّر مكانه بعده (افتراضيًا دقيقتان — الإعدادات §11).
  final DateTime? offerExpiresAt;

  bool get isOffer => outcome == QuoteOutcome.offer;

  factory Quote.fromJson(Map<String, dynamic> json) => Quote(
        barberId: json['barberId'] as String,
        barberName: json['barberName'] as String?,
        start: parseUtc(json['start'] as String),
        end: parseUtc(json['end'] as String),
        durationMin: (json['durationMin'] as num).toInt(),
        priceCents: (json['price'] as num).toInt(),
        outcome: QuoteOutcome.fromWire(json['outcome'] as String),
        offerId: json['offerId'] as String?,
        offerExpiresAt: parseUtcOrNull(json['offerExpiresAt'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'barberId': barberId,
        'barberName': barberName,
        'start': toIso(start),
        'end': toIso(end),
        'durationMin': durationMin,
        'price': priceCents,
        'outcome': outcome.toWire(),
        'offerId': offerId,
        'offerExpiresAt': toIsoOrNull(offerExpiresAt),
      };
}

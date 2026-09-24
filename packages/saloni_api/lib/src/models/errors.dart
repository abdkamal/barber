import 'quote.dart';

/// خطأ واجهة برمجية موحّد، كما يعيده السيرفر:
/// `{"error": {"code": "SLOT_UNAVAILABLE", "message": "نص عربي للعرض", "details"?: …}}`
/// انظر docs/api.md §"قواعد عامة".
class ApiError implements Exception {
  const ApiError({
    required this.code,
    required this.message,
    this.statusCode,
    this.retryAfter,
    this.details,
  });

  /// رمز الخطأ الثابت من السيرفر (مثلاً `SLOT_UNAVAILABLE`).
  final String code;

  /// رسالة عربية جاهزة للعرض للمستخدم.
  final String message;

  /// حالة HTTP إن وُجدت.
  final int? statusCode;

  /// مهلة إعادة المحاولة عند 429 (`Retry-After`).
  final Duration? retryAfter;

  /// تفاصيل إضافية يرسلها السيرفر مع بعض الأخطاء (مثل عرض أقرب وقت عند
  /// تعذّر تعديل الوقت، أو البدائل عند تعذّر النقل)، كما وردت.
  final Object? details;

  /// رموز الأخطاء المحلية التي لا تعني رفضًا من السيرفر — يمكن إعادة المحاولة.
  static const networkCodes = {'NETWORK_ERROR', 'TIMEOUT'};

  /// فشل اتصال/مهلة (لم يصل رد من السيرفر) — مؤقت وقابل لإعادة المحاولة.
  bool get isNetwork => networkCodes.contains(code);

  /// انتهت الجلسة ولم يعد التجديد ممكنًا — يلزم الدخول من جديد.
  bool get isSignedOut => code == 'SIGNED_OUT';

  /// حساب الزبون بانتظار اعتماد الصالون (`403 ACCOUNT_PENDING`).
  bool get isAccountPending => code == 'ACCOUNT_PENDING';

  /// الحساب أو الصالون موقوف — يظهر عند الدخول فقط (`403 ACCOUNT_SUSPENDED`
  /// أو `SALON_SUSPENDED`)؛ إبطال الجلسات الناتج عنه يصل لاحقًا بـ401 عامّ لا
  /// يميَّز عن إبطال جلسة عادي (docs/api.md).
  bool get isAccountSuspended =>
      code == 'ACCOUNT_SUSPENDED' || code == 'SALON_SUSPENDED';

  Map<String, dynamic>? get _detailsMap =>
      details is Map ? Map<String, dynamic>.from(details as Map) : null;

  /// `POST /bookings/{id}/change-time` → `409 SLOT_UNAVAILABLE`: أقرب وقت
  /// محجوز مؤقتًا (بصيغة `quote`)؛ قبوله `createBooking(offerId: …)` ينقل
  /// الحجز نفسه، والحجز الحالي يبقى كما هو حتى ذلك.
  Quote? get changeTimeOffer {
    final offer = _detailsMap?['offer'];
    if (offer is! Map) return null;
    try {
      return Quote.fromJson(Map<String, dynamic>.from(offer));
    } catch (_) {
      return null;
    }
  }

  /// `POST /manager/bookings/{id}/transfer` → `409 TRANSFER_NO_SLOT`: حلاقون
  /// آخرون يتسع وقتهم (الأبكر أولًا).
  List<TransferAlternative> get transferAlternatives {
    final list = _detailsMap?['alternatives'];
    if (list is! List) return const [];
    return [
      for (final e in list)
        if (e is Map) TransferAlternative.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  factory ApiError.fromJson(Map<String, dynamic> json, {int? statusCode}) {
    final error = json['error'];
    if (error is Map) {
      return ApiError(
        code: error['code'] as String? ?? 'UNKNOWN',
        message: error['message'] as String? ?? 'حدث خطأ غير متوقع',
        statusCode: statusCode,
        details: error['details'],
      );
    }
    return ApiError(
      code: 'UNKNOWN',
      message: 'حدث خطأ غير متوقع',
      statusCode: statusCode,
    );
  }

  /// خطأ شبكة لا يأتي من السيرفر (لا يوجد جسم استجابة صالح).
  factory ApiError.network(String message) =>
      ApiError(code: 'NETWORK_ERROR', message: message);

  factory ApiError.timeout() =>
      const ApiError(code: 'TIMEOUT', message: 'انتهت مهلة الاتصال بالسيرفر');

  factory ApiError.signedOut() => const ApiError(
        code: 'SIGNED_OUT',
        message: 'انتهت الجلسة، الرجاء تسجيل الدخول مجددًا',
      );

  factory ApiError.rateLimited(Duration retryAfter) => ApiError(
        code: 'RATE_LIMITED',
        message: 'محاولات كثيرة، الرجاء المحاولة لاحقًا',
        statusCode: 429,
        retryAfter: retryAfter,
      );

  @override
  String toString() => 'ApiError($code: $message)';
}

/// بديل مقترح عند تعذّر النقل: `{barberId, barberName, start, end}`.
class TransferAlternative {
  const TransferAlternative({
    required this.barberId,
    required this.barberName,
    required this.start,
    required this.end,
  });

  final String barberId;
  final String barberName;
  final DateTime start;
  final DateTime end;

  factory TransferAlternative.fromJson(Map<String, dynamic> json) =>
      TransferAlternative(
        barberId: json['barberId'] as String,
        barberName: json['barberName'] as String? ?? '',
        start: DateTime.parse(json['start'] as String).toUtc(),
        end: DateTime.parse(json['end'] as String).toUtc(),
      );
}

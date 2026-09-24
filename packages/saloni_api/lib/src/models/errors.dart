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
    this.requestId,
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

  /// معرّف الطلب من السيرفر (ترويسة `X-Request-Id`، أو `error.requestId` في
  /// ردود 500) — يطابق سطر سجل السيرفر؛ يُعرض مختصرًا ليبلّغ به المستخدم.
  final String? requestId;

  /// آخر 6 محارف من [requestId] (للعرض: «رمز: …»)، أو `null`.
  String? get shortRequestId {
    final id = requestId;
    if (id == null || id.isEmpty) return null;
    final clean = id.replaceAll('-', '');
    return clean.length <= 6 ? clean : clean.substring(clean.length - 6);
  }

  /// `400 VALIDATION_FAILED`: الحقول المرفوضة `[{path, code}]` كما أرسلها
  /// السيرفر (المسار ورمز المشكلة فقط، بلا قيم).
  List<ValidationIssue> get validationIssues {
    final d = details;
    if (d is! List) return const [];
    return [
      for (final e in d)
        if (e is Map)
          ValidationIssue(
            path: '${e['path'] ?? ''}',
            code: '${e['code'] ?? ''}',
          ),
    ];
  }

  /// نوع فشل الشبكة (لم يصل رد من السيرفر): لا إنترنت، أو السيرفر لا يُصل،
  /// أو انتهت المهلة. `null` إن لم يكن خطأ شبكة.
  NetworkFailure? get networkFailure {
    if (code == 'TIMEOUT') return NetworkFailure.timeout;
    if (code != 'NETWORK_ERROR') return null;
    final m = message.toLowerCase();
    const noInternet = [
      'failed host lookup',
      'network is unreachable',
      'no address associated',
      'nodename nor servname',
      'enetunreach',
      'no route to host',
      'errno = 7',
      'errno = 101',
      'software caused connection abort',
    ];
    if (noInternet.any(m.contains)) return NetworkFailure.noInternet;
    if (m.contains('timed out')) return NetworkFailure.timeout;
    return NetworkFailure.serverUnreachable;
  }

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

  /// ق40: رفع إجراءات حساب **غير موقوف** عبر مسار المدير (`409
  /// ACCOUNT_NOT_SUSPENDED`) — يرفعها صاحب الحساب بنفسه عند دخوله.
  bool get isAccountNotSuspended => code == 'ACCOUNT_NOT_SUSPENDED';

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

  factory ApiError.fromJson(Map<String, dynamic> json,
      {int? statusCode, String? requestId}) {
    final error = json['error'];
    if (error is Map) {
      final code = error['code'];
      final message = error['message'];
      final bodyId = error['requestId'];
      return ApiError(
        code: code is String ? code : 'UNKNOWN',
        message: message is String ? message : 'حدث خطأ غير متوقع',
        statusCode: statusCode,
        details: error['details'],
        requestId: bodyId is String ? bodyId : requestId,
      );
    }
    return ApiError(
      code: 'UNKNOWN',
      message: 'حدث خطأ غير متوقع',
      statusCode: statusCode,
      requestId: requestId,
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
  String toString() => 'ApiError($code: $message'
      '${statusCode == null ? '' : ', http $statusCode'}'
      '${requestId == null ? '' : ', request $requestId'})';
}

/// حقل رفضه تحقق السيرفر (`VALIDATION_FAILED`): المسار (`salon.timezone`،
/// `owner.username`…) ورمز المشكلة (`invalid_timezone`، `too_small`…).
class ValidationIssue {
  const ValidationIssue({required this.path, required this.code});
  final String path;
  final String code;

  @override
  String toString() => '$path:$code';
}

/// أنواع فشل الاتصال (لم يصل رد من السيرفر).
enum NetworkFailure {
  /// لا اتصال بالإنترنت (تعذّر حلّ الاسم، الشبكة غير متاحة).
  noInternet,

  /// الإنترنت متاح لكن السيرفر لا يُصل (رُفض الاتصال، قُطع، شهادة…).
  serverUnreachable,

  /// انتهت مهلة الاتصال.
  timeout,
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

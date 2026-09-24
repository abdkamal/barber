/// خطأ واجهة برمجية موحّد، كما يعيده السيرفر:
/// `{"error": {"code": "SLOT_UNAVAILABLE", "message": "نص عربي للعرض"}}`
/// انظر docs/api.md §"قواعد عامة".
class ApiError implements Exception {
  const ApiError({
    required this.code,
    required this.message,
    this.statusCode,
    this.retryAfter,
  });

  /// رمز الخطأ الثابت من السيرفر (مثلاً `SLOT_UNAVAILABLE`).
  final String code;

  /// رسالة عربية جاهزة للعرض للمستخدم.
  final String message;

  /// حالة HTTP إن وُجدت.
  final int? statusCode;

  /// مهلة إعادة المحاولة عند 429 (`Retry-After`).
  final Duration? retryAfter;

  factory ApiError.fromJson(Map<String, dynamic> json, {int? statusCode}) {
    final error = json['error'];
    if (error is Map<String, dynamic>) {
      return ApiError(
        code: error['code'] as String? ?? 'UNKNOWN',
        message: error['message'] as String? ?? 'حدث خطأ غير متوقع',
        statusCode: statusCode,
      );
    }
    return ApiError(
      code: 'UNKNOWN',
      message: 'حدث خطأ غير متوقع',
      statusCode: statusCode,
    );
  }

  /// خطأ شبكة/مهلة لا يأتي من السيرفر (لا يوجد جسم استجابة صالح).
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

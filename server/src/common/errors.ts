import { HttpException, HttpStatus } from '@nestjs/common';

/**
 * API error with the contract shape (docs/api.md):
 *   {"error": {"code": "UPPER_SNAKE", "message": "نص عربي"}}
 */
export class ApiError extends HttpException {
  constructor(
    status: HttpStatus,
    readonly code: string,
    message: string,
    readonly retryAfterSec?: number,
    readonly details?: unknown,
  ) {
    super({ error: { code, message, ...(details !== undefined ? { details } : {}) } }, status);
  }
}

export const Errors = {
  validation: (details?: unknown) =>
    new ApiError(HttpStatus.BAD_REQUEST, 'VALIDATION_FAILED', 'البيانات المدخلة غير صحيحة', undefined, details),
  unauthenticated: () => new ApiError(HttpStatus.UNAUTHORIZED, 'UNAUTHENTICATED', 'يلزم تسجيل الدخول'),
  invalidCredentials: () =>
    new ApiError(HttpStatus.UNAUTHORIZED, 'INVALID_CREDENTIALS', 'بيانات الدخول غير صحيحة'),
  invalidRefreshToken: () =>
    new ApiError(HttpStatus.UNAUTHORIZED, 'INVALID_REFRESH_TOKEN', 'انتهت الجلسة، يرجى تسجيل الدخول من جديد'),
  refreshTokenReused: () =>
    new ApiError(HttpStatus.UNAUTHORIZED, 'REFRESH_TOKEN_REUSED', 'أُلغيت الجلسة لأسباب أمنية، يرجى تسجيل الدخول من جديد'),
  forbidden: () => new ApiError(HttpStatus.FORBIDDEN, 'FORBIDDEN', 'ليست لديك صلاحية لهذا الإجراء'),
  accountSuspended: () => new ApiError(HttpStatus.FORBIDDEN, 'ACCOUNT_SUSPENDED', 'هذا الحساب موقوف'),
  salonSuspended: () => new ApiError(HttpStatus.FORBIDDEN, 'SALON_SUSPENDED', 'هذا الصالون موقوف حاليًا'),
  salonNotFound: () => new ApiError(HttpStatus.NOT_FOUND, 'SALON_NOT_FOUND', 'لم نجد صالونًا بهذا الرمز'),
  notFound: () => new ApiError(HttpStatus.NOT_FOUND, 'NOT_FOUND', 'العنصر غير موجود'),
  /** Review L4: generic — never says whether the number already has an account. */
  registrationFailed: () =>
    new ApiError(
      HttpStatus.CONFLICT,
      'REGISTRATION_FAILED',
      'تعذّر إنشاء الحساب بهذه البيانات. إن كان لديك حساب في هذا الصالون فسجّل الدخول، أو اطلب رمز إعادة التعيين من الصالون',
    ),
  usernameTaken: () => new ApiError(HttpStatus.CONFLICT, 'USERNAME_TAKEN', 'اسم المستخدم مستخدم مسبقًا'),
  invalidResetCode: () =>
    new ApiError(HttpStatus.BAD_REQUEST, 'INVALID_RESET_CODE', 'رمز إعادة التعيين غير صحيح أو منتهي'),
  weakPassword: (min: number) =>
    new ApiError(HttpStatus.BAD_REQUEST, 'WEAK_PASSWORD', `كلمة المرور يجب ألا تقل عن ${min} أحرف`),
  tooManyRequests: (retryAfterSec: number) =>
    new ApiError(HttpStatus.TOO_MANY_REQUESTS, 'RATE_LIMITED', 'محاولات كثيرة، يرجى المحاولة لاحقًا', retryAfterSec),
  loginBackoff: (retryAfterSec: number) =>
    new ApiError(
      HttpStatus.TOO_MANY_REQUESTS,
      'LOGIN_BACKOFF',
      'محاولات دخول فاشلة متكررة، يرجى الانتظار قليلًا ثم المحاولة',
      retryAfterSec,
    ),
  conflict: (code: string, message: string) => new ApiError(HttpStatus.CONFLICT, code, message),
  internal: () => new ApiError(HttpStatus.INTERNAL_SERVER_ERROR, 'INTERNAL', 'حدث خطأ غير متوقع'),
};

/** Review L8: upper bounds for money (minor units: 1,000,000.00) and a single service's base duration (8 h). */
export const MAX_PRICE_MINOR = 100_000_000;
export const MAX_SERVICE_MINUTES = 480;

import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger } from '@nestjs/common';
import type { Response, Request } from 'express';
import { ApiError } from './errors';

const GENERIC: Record<number, { code: string; message: string }> = {
  400: { code: 'BAD_REQUEST', message: 'طلب غير صالح' },
  401: { code: 'UNAUTHENTICATED', message: 'يلزم تسجيل الدخول' },
  403: { code: 'FORBIDDEN', message: 'ليست لديك صلاحية لهذا الإجراء' },
  404: { code: 'NOT_FOUND', message: 'غير موجود' },
  405: { code: 'METHOD_NOT_ALLOWED', message: 'طريقة غير مسموحة' },
  413: { code: 'PAYLOAD_TOO_LARGE', message: 'حجم الطلب كبير جدًا' },
  415: { code: 'UNSUPPORTED_MEDIA_TYPE', message: 'نوع المحتوى غير مدعوم' },
  429: { code: 'RATE_LIMITED', message: 'محاولات كثيرة، يرجى المحاولة لاحقًا' },
};

/**
 * Normalises every error to {"error":{"code","message"}}. Never echoes request data and never logs
 * request bodies (they may contain passwords / tokens).
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger('HTTP');

  catch(exception: unknown, host: ArgumentsHost): void {
    const res = host.switchToHttp().getResponse<Response>();
    const req = host.switchToHttp().getRequest<Request>();

    if (exception instanceof ApiError) {
      if (exception.retryAfterSec !== undefined) res.setHeader('Retry-After', String(exception.retryAfterSec));
      res.status(exception.getStatus()).json(exception.getResponse());
      return;
    }
    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const g = GENERIC[status] ?? { code: 'HTTP_ERROR', message: 'تعذر تنفيذ الطلب' };
      res.status(status).json({ error: g });
      return;
    }
    // body-parser errors (malformed JSON, too large) are plain errors carrying a status.
    const maybe = exception as { status?: number; type?: string };
    if (typeof maybe?.status === 'number' && maybe.status >= 400 && maybe.status < 500) {
      const g = GENERIC[maybe.status] ?? GENERIC[400]!;
      res.status(maybe.status).json({ error: g });
      return;
    }
    const err = exception as Error;
    this.logger.error(`Unhandled error on ${req.method} ${req.route?.path ?? '(unknown route)'}: ${err?.name}: ${err?.message}`, err?.stack);
    res.status(HttpStatus.INTERNAL_SERVER_ERROR).json({ error: { code: 'INTERNAL_ERROR', message: 'حدث خطأ غير متوقع' } });
  }
}

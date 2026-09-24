import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger } from '@nestjs/common';
import type { Response, Request } from 'express';
import { ApiError } from './errors';
import { requestIdOf } from './request-id';

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

/** Code of an unhandled server error (phase 11: was INTERNAL_ERROR). */
export const INTERNAL_CODE = 'INTERNAL';

/**
 * Where the request went, for logs: the matched route pattern (`/v1/manager/bookings/:id/transfer`)
 * when there is one — never the query string (it may carry tokens) nor the body (passwords).
 */
export function routeOf(req: Request): string {
  const pattern = (req.route as { path?: string } | undefined)?.path;
  if (pattern) return `${req.baseUrl ?? ''}${pattern}`;
  return (req.originalUrl ?? req.url ?? '').split('?')[0] || '(unknown route)';
}

/**
 * Normalises every error to {"error":{"code","message"}}. Never echoes request data and never logs
 * request bodies, query strings or headers (they may contain passwords / tokens).
 *
 * Phase 11 (trial feedback — diagnosable failures): every response carries `X-Request-Id`
 * (request-id.ts). Unhandled errors are logged with that id, the method + route and the stack, and
 * answered `500 {"error": {"code": "INTERNAL", "message", "requestId"}}` so the user can report the
 * code the app shows. Handled 4xx/5xx errors are logged on one line (id, route, status, code — and
 * for VALIDATION_FAILED the failing paths/issue codes, which never contain values).
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger('HTTP');

  catch(exception: unknown, host: ArgumentsHost): void {
    const res = host.switchToHttp().getResponse<Response>();
    const req = host.switchToHttp().getRequest<Request>();
    const requestId = requestIdOf(req);
    const where = `[${requestId ?? '-'}] ${req.method} ${routeOf(req)}`;

    if (exception instanceof ApiError) {
      if (exception.retryAfterSec !== undefined) res.setHeader('Retry-After', String(exception.retryAfterSec));
      const status = exception.getStatus();
      const details = exception.code === 'VALIDATION_FAILED' && exception.details !== undefined ? ` ${safeJson(exception.details)}` : '';
      const line = `${where} -> ${status} ${exception.code}${details}`;
      if (status >= 500) this.logger.error(line);
      else if (status !== 401 && status !== 404) this.logger.warn(line);
      const body = exception.getResponse() as { error: Record<string, unknown> };
      res.status(status).json(status >= 500 && requestId ? { error: { ...body.error, requestId } } : body);
      return;
    }
    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const g = GENERIC[status] ?? { code: 'HTTP_ERROR', message: 'تعذر تنفيذ الطلب' };
      if (status >= 500) this.logger.error(`${where} -> ${status} ${exception.name}: ${exception.message}`, exception.stack);
      res.status(status).json({ error: status >= 500 && requestId ? { ...g, requestId } : g });
      return;
    }
    // body-parser errors (malformed JSON, too large) are plain errors carrying a status.
    const maybe = exception as { status?: number; type?: string };
    if (typeof maybe?.status === 'number' && maybe.status >= 400 && maybe.status < 500) {
      const g = GENERIC[maybe.status] ?? GENERIC[400]!;
      this.logger.warn(`${where} -> ${maybe.status} ${g.code}${maybe.type ? ` (${maybe.type})` : ''}`);
      res.status(maybe.status).json({ error: g });
      return;
    }
    const err = exception as Error;
    this.logger.error(`${where} -> 500 unhandled ${err?.name ?? typeof exception}: ${err?.message ?? String(exception)}`, err?.stack);
    if (res.headersSent) return;
    res.status(HttpStatus.INTERNAL_SERVER_ERROR).json({
      error: { code: INTERNAL_CODE, message: 'حدث خطأ غير متوقع', ...(requestId ? { requestId } : {}) },
    });
  }
}

function safeJson(v: unknown): string {
  try {
    return JSON.stringify(v).slice(0, 500);
  } catch {
    return '';
  }
}

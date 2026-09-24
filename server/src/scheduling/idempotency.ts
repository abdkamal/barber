import { HttpStatus } from '@nestjs/common';
import { ApiError, Errors } from '../common/errors';
import type { TenantQueryable } from '../tenancy/tenant-context';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Validates the optional `Idempotency-Key` header (UUID). */
export function idempotencyKey(header: string | string[] | undefined): string | null {
  if (header === undefined) return null;
  const v = Array.isArray(header) ? header[0] : header;
  if (!v || !UUID_RE.test(v.trim())) throw Errors.validation([{ path: 'Idempotency-Key', code: 'invalid_uuid' }]);
  return v.trim().toLowerCase();
}

export interface IdemSubject {
  kind: 'staff' | 'customer';
  id: string;
}

/** A result that may be an API error which must still be remembered (e.g. an offer instead of a move). */
export interface Outcome<T> {
  status: number;
  body: T;
}

/**
 * Runs `fn` at most once per (subject, key) inside the caller's transaction (api.md "قواعد عامة").
 * A concurrent duplicate blocks on the key row until the first commits, then gets its stored
 * result; a failed first attempt rolls back and leaves the key free.
 */
export async function once<T>(
  q: TenantQueryable,
  subject: IdemSubject,
  key: string | null,
  scope: string,
  fn: () => Promise<Outcome<T>>,
): Promise<Outcome<T>> {
  if (!key) return fn();
  const ins = await q.query(
    `INSERT INTO idempotency_keys (subject_kind, subject_id, key, scope, status_code, response)
     VALUES ($1, $2, $3, $4, 0, 'null'::jsonb) ON CONFLICT DO NOTHING RETURNING 1`,
    [subject.kind, subject.id, key, scope],
  );
  if (!ins.rowCount) {
    const { rows } = await q.query<{ scope: string; status_code: number; response: T }>(
      'SELECT scope, status_code, response FROM idempotency_keys WHERE subject_kind = $1 AND subject_id = $2 AND key = $3',
      [subject.kind, subject.id, key],
    );
    const r = rows[0]!;
    if (r.scope !== scope) {
      throw new ApiError(HttpStatus.UNPROCESSABLE_ENTITY, 'IDEMPOTENCY_KEY_REUSED', 'تم استخدام مفتاح الطلب لعملية أخرى');
    }
    return { status: r.status_code, body: r.response };
  }
  const out = await fn();
  await q.query(
    'UPDATE idempotency_keys SET status_code = $4, response = $5 WHERE subject_kind = $1 AND subject_id = $2 AND key = $3',
    [subject.kind, subject.id, key, out.status, JSON.stringify(out.body ?? null)],
  );
  return out;
}

/** Turns a remembered error outcome back into the HTTP error. */
export function unwrap<T>(o: Outcome<T>): T {
  if (o.status >= 400) {
    const e = (o.body as { error?: { code: string; message: string; details?: unknown } }).error;
    throw new ApiError(o.status, e?.code ?? 'ERROR', e?.message ?? 'تعذر تنفيذ الطلب', undefined, e?.details);
  }
  return o.body;
}

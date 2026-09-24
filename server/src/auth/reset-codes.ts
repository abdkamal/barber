import { createHmac, randomInt, timingSafeEqual } from 'node:crypto';
import type { TenantQueryable } from '../tenancy/tenant-context';
import type { SubjectKind } from './principal';

/** Unambiguous alphabet (no 0/O, 1/I/L). 10 symbols ≈ 49 bits. */
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const LENGTH = 10;
export const MAX_RESET_ATTEMPTS = 5;

export function generateResetCode(): string {
  let s = '';
  for (let i = 0; i < LENGTH; i++) s += ALPHABET[randomInt(ALPHABET.length)];
  return `${s.slice(0, 5)}-${s.slice(5)}`;
}

export function normalizeResetCode(input: string): string {
  return input.toUpperCase().replace(/[\s-]/g, '');
}

/** HMAC with a server-side pepper, bound to the salon, so a leaked DB alone cannot brute-force codes. */
export function hashResetCode(pepper: string, salonId: string, code: string): string {
  return createHmac('sha256', pepper).update(`${salonId}:${normalizeResetCode(code)}`).digest('hex');
}

export function resetCodeMatches(pepper: string, salonId: string, code: string, storedHash: string): boolean {
  const a = Buffer.from(hashResetCode(pepper, salonId, code), 'hex');
  const b = Buffer.from(storedHash, 'hex');
  return a.length === b.length && timingSafeEqual(a, b);
}

export interface ActiveResetCode {
  id: string;
  subject_kind: SubjectKind;
  subject_id: string;
  code_hash: string;
  failed_attempts: number;
}

export const ResetCodesRepo = {
  /** Issues a new code for the subject, invalidating any earlier unused ones. */
  async issue(
    q: TenantQueryable,
    r: { subjectKind: SubjectKind; subjectId: string; codeHash: string; ttlHours: number; issuedBy: { kind: 'staff'; staffId: string } | { kind: 'vendor' } },
  ): Promise<{ id: string; expires_at: Date }> {
    await q.query(
      `UPDATE reset_codes SET invalidated_at = now()
        WHERE subject_kind = $1 AND subject_id = $2 AND used_at IS NULL AND invalidated_at IS NULL`,
      [r.subjectKind, r.subjectId],
    );
    const { rows } = await q.query<{ id: string; expires_at: Date }>(
      `INSERT INTO reset_codes (subject_kind, subject_id, code_hash, expires_at, issued_by_kind, issued_by_staff_id)
       VALUES ($1, $2, $3, now() + make_interval(hours => $4), $5, $6) RETURNING id, expires_at`,
      [r.subjectKind, r.subjectId, r.codeHash, r.ttlHours, r.issuedBy.kind, r.issuedBy.kind === 'staff' ? r.issuedBy.staffId : null],
    );
    return rows[0]!;
  },

  async findActive(q: TenantQueryable, kind: SubjectKind, subjectId: string, forUpdate = false): Promise<ActiveResetCode | null> {
    const { rows } = await q.query<ActiveResetCode>(
      `SELECT id, subject_kind, subject_id, code_hash, failed_attempts FROM reset_codes
        WHERE subject_kind = $1 AND subject_id = $2 AND used_at IS NULL AND invalidated_at IS NULL AND expires_at > now()
        ORDER BY created_at DESC LIMIT 1 ${forUpdate ? 'FOR UPDATE' : ''}`,
      [kind, subjectId],
    );
    return rows[0] ?? null;
  },

  async recordFailure(q: TenantQueryable, id: string): Promise<void> {
    await q.query(
      `UPDATE reset_codes SET failed_attempts = failed_attempts + 1,
          invalidated_at = CASE WHEN failed_attempts + 1 >= $2 THEN now() ELSE invalidated_at END
        WHERE id = $1`,
      [id, MAX_RESET_ATTEMPTS],
    );
  },

  async markUsed(q: TenantQueryable, id: string): Promise<boolean> {
    const { rowCount } = await q.query('UPDATE reset_codes SET used_at = now() WHERE id = $1 AND used_at IS NULL', [id]);
    return (rowCount ?? 0) === 1;
  },
};

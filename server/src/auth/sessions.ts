import { randomUUID } from 'node:crypto';
import type { TenantContext, TenantQueryable } from '../tenancy/tenant-context';
import type { SubjectKind } from './principal';

/** Sessions (refresh-token families) and their rotating refresh tokens, in the salon DB. */
export const SessionsRepo = {
  async create(q: TenantQueryable, kind: SubjectKind, subjectId: string): Promise<string> {
    const id = randomUUID();
    await q.query('INSERT INTO sessions (id, subject_kind, subject_id) VALUES ($1, $2, $3)', [id, kind, subjectId]);
    return id;
  },

  async addRefreshToken(q: TenantQueryable, r: { id: string; sessionId: string; tokenHash: string; expiresAt: Date }): Promise<void> {
    await q.query('INSERT INTO refresh_tokens (id, session_id, token_hash, expires_at) VALUES ($1, $2, $3, $4)', [
      r.id,
      r.sessionId,
      r.tokenHash,
      r.expiresAt,
    ]);
  },

  async lockRefreshToken(q: TenantQueryable, jti: string) {
    const { rows } = await q.query<{
      id: string;
      session_id: string;
      token_hash: string;
      expired: boolean;
      used_at: Date | null;
      revoked_at: Date | null;
      subject_kind: SubjectKind;
      subject_id: string;
      session_revoked_at: Date | null;
    }>(
      `SELECT rt.id, rt.session_id, rt.token_hash, rt.expires_at <= now() AS expired, rt.used_at, rt.revoked_at,
              s.subject_kind, s.subject_id, s.revoked_at AS session_revoked_at
         FROM refresh_tokens rt JOIN sessions s ON s.id = rt.session_id
        WHERE rt.id = $1
        FOR UPDATE OF rt, s`,
      [jti],
    );
    return rows[0] ?? null;
  },

  async markRotated(q: TenantQueryable, jti: string, replacedBy: string): Promise<void> {
    await q.query('UPDATE refresh_tokens SET used_at = now(), replaced_by = $2 WHERE id = $1', [jti, replacedBy]);
    await q.query(
      'UPDATE sessions SET last_refreshed_at = now() WHERE id = (SELECT session_id FROM refresh_tokens WHERE id = $1)',
      [jti],
    );
  },

  async revokeSession(q: TenantQueryable, sessionId: string, reason: string): Promise<void> {
    await q.query('UPDATE sessions SET revoked_at = now(), revoked_reason = $2 WHERE id = $1 AND revoked_at IS NULL', [
      sessionId,
      reason,
    ]);
    await q.query('UPDATE refresh_tokens SET revoked_at = now() WHERE session_id = $1 AND revoked_at IS NULL', [sessionId]);
  },

  async revokeAllFor(q: TenantQueryable, kind: SubjectKind, subjectId: string, reason: string): Promise<number> {
    const { rowCount } = await q.query(
      `UPDATE sessions SET revoked_at = now(), revoked_reason = $3
        WHERE subject_kind = $1 AND subject_id = $2 AND revoked_at IS NULL`,
      [kind, subjectId, reason],
    );
    await q.query(
      `UPDATE refresh_tokens SET revoked_at = now()
        WHERE revoked_at IS NULL AND session_id IN (SELECT id FROM sessions WHERE subject_kind = $1 AND subject_id = $2)`,
      [kind, subjectId],
    );
    return rowCount ?? 0;
  },

  /** Is the session alive? Used by the access-token guard on every request. */
  async isActive(t: TenantContext, sessionId: string, kind: SubjectKind, subjectId: string): Promise<boolean> {
    const { rowCount } = await t.db.query(
      'SELECT 1 FROM sessions WHERE id = $1 AND subject_kind = $2 AND subject_id = $3 AND revoked_at IS NULL',
      [sessionId, kind, subjectId],
    );
    return (rowCount ?? 0) > 0;
  },
};

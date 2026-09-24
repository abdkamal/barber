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

  async addRefreshToken(q: TenantQueryable, r: { id: string; sessionId: string; tokenHash: string; expiresAt: Date; siblingId?: string | null }): Promise<void> {
    await q.query('INSERT INTO refresh_tokens (id, session_id, token_hash, expires_at, sibling_id) VALUES ($1, $2, $3, $4, $5)', [
      r.id,
      r.sessionId,
      r.tokenHash,
      r.expiresAt,
      r.siblingId ?? null,
    ]);
  },

  /** Locks a refresh token and its session. `graceSec` decides `used_within_grace` (round 2, item 7). */
  async lockRefreshToken(q: TenantQueryable, jti: string, graceSec = 0) {
    const { rows } = await q.query<{
      id: string;
      session_id: string;
      token_hash: string;
      expired: boolean;
      used_at: Date | null;
      used_within_grace: boolean;
      replaced_by: string | null;
      grace_used_at: Date | null;
      sibling_id: string | null;
      revoked_at: Date | null;
      subject_kind: SubjectKind;
      subject_id: string;
      session_revoked_at: Date | null;
    }>(
      `SELECT rt.id, rt.session_id, rt.token_hash, rt.expires_at <= now() AS expired, rt.used_at,
              (rt.used_at IS NOT NULL AND rt.used_at > now() - make_interval(secs => $2::double precision)) AS used_within_grace,
              rt.replaced_by, rt.grace_used_at, rt.sibling_id, rt.revoked_at,
              s.subject_kind, s.subject_id, s.revoked_at AS session_revoked_at
         FROM refresh_tokens rt JOIN sessions s ON s.id = rt.session_id
        WHERE rt.id = $1
        FOR UPDATE OF rt, s`,
      [jti, graceSec],
    );
    return rows[0] ?? null;
  },

  /** Is this token the live head of its session (never rotated, never revoked)? Locks it. */
  async lockLiveToken(q: TenantQueryable, jti: string, sessionId: string): Promise<boolean> {
    const { rowCount } = await q.query(
      'SELECT 1 FROM refresh_tokens WHERE id = $1 AND session_id = $2 AND used_at IS NULL AND revoked_at IS NULL AND expires_at > now() FOR UPDATE',
      [jti, sessionId],
    );
    return (rowCount ?? 0) > 0;
  },

  async markRotated(q: TenantQueryable, jti: string, replacedBy: string): Promise<void> {
    await q.query('UPDATE refresh_tokens SET used_at = now(), replaced_by = $2 WHERE id = $1', [jti, replacedBy]);
    await q.query(
      'UPDATE sessions SET last_refreshed_at = now() WHERE id = (SELECT session_id FROM refresh_tokens WHERE id = $1)',
      [jti],
    );
    // A grace re-issue left two parallel tokens: rotating one retires the other (one live branch).
    await q.query(
      `UPDATE refresh_tokens SET revoked_at = now()
        WHERE id = (SELECT sibling_id FROM refresh_tokens WHERE id = $1) AND used_at IS NULL AND revoked_at IS NULL`,
      [jti],
    );
  },

  /** Round 2 (item 7): records the one grace re-issue of `jti` and links the two parallel successors. */
  async markGraceReissue(q: TenantQueryable, jti: string, successor: string, reissued: string): Promise<void> {
    await q.query('UPDATE refresh_tokens SET grace_used_at = now() WHERE id = $1', [jti]);
    await q.query('UPDATE refresh_tokens SET sibling_id = $2 WHERE id = $1', [successor, reissued]);
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

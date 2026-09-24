import type { TenantQueryable } from '../tenancy/tenant-context';

export interface StaffRow {
  id: string;
  name: string;
  username: string;
  password_hash: string;
  role: 'barber' | 'manager';
  active: boolean;
  is_owner: boolean;
  call_ahead_minutes: number;
  token_version: number;
  /** ق40: when the account was last suspended (null while active). */
  suspended_at: Date | null;
  created_at: Date;
  last_login_at: Date | null;
}

export type StaffPublic = Omit<StaffRow, 'password_hash' | 'token_version'>;

const PUBLIC_COLS = 'id, name, username, role, active, is_owner, call_ahead_minutes, created_at, last_login_at, suspended_at';

export function toStaffPublic(r: StaffRow | StaffPublic): StaffPublic {
  return {
    id: r.id,
    name: r.name,
    username: r.username,
    role: r.role,
    active: r.active,
    is_owner: r.is_owner,
    call_ahead_minutes: r.call_ahead_minutes,
    created_at: r.created_at,
    last_login_at: r.last_login_at,
    suspended_at: r.suspended_at,
  };
}

/** Staff queries. `q` must be a tenant-bound handle (TenantContext.db or a transaction of it). */
export const StaffRepo = {
  async findByUsername(q: TenantQueryable, username: string): Promise<StaffRow | null> {
    const { rows } = await q.query<StaffRow>('SELECT * FROM staff WHERE username = $1', [username]);
    return rows[0] ?? null;
  },

  async findById(q: TenantQueryable, id: string): Promise<StaffRow | null> {
    const { rows } = await q.query<StaffRow>('SELECT * FROM staff WHERE id = $1', [id]);
    return rows[0] ?? null;
  },

  async list(q: TenantQueryable): Promise<StaffPublic[]> {
    const { rows } = await q.query<StaffPublic>(`SELECT ${PUBLIC_COLS} FROM staff ORDER BY created_at`);
    return rows;
  },

  async insert(
    q: TenantQueryable,
    s: { name: string; username: string; passwordHash: string; role: 'barber' | 'manager'; isOwner?: boolean },
  ): Promise<StaffPublic> {
    const { rows } = await q.query<StaffPublic>(
      `INSERT INTO staff (name, username, password_hash, role, is_owner) VALUES ($1, $2, $3, $4, $5) RETURNING ${PUBLIC_COLS}`,
      [s.name, s.username, s.passwordHash, s.role, !!s.isOwner],
    );
    return rows[0]!;
  },

  async update(
    q: TenantQueryable,
    id: string,
    patch: { name?: string; role?: 'barber' | 'manager'; active?: boolean; callAheadMinutes?: number },
    bumpTokenVersion: boolean,
    now: Date = new Date(),
  ): Promise<StaffPublic | null> {
    // ق40: the suspension time is recorded when the account goes active → inactive, kept while it
    // stays suspended, and cleared when it is reactivated (SET expressions read the old row).
    const { rows } = await q.query<StaffPublic>(
      `UPDATE staff SET
         name = COALESCE($2, name),
         role = COALESCE($3, role),
         suspended_at = CASE WHEN $4::boolean IS NULL THEN suspended_at
                             WHEN $4::boolean THEN NULL
                             WHEN active THEN $7::timestamptz
                             ELSE COALESCE(suspended_at, $7::timestamptz) END,
         active = COALESCE($4, active),
         call_ahead_minutes = COALESCE($5, call_ahead_minutes),
         token_version = token_version + CASE WHEN $6 THEN 1 ELSE 0 END,
         updated_at = now()
       WHERE id = $1 RETURNING ${PUBLIC_COLS}`,
      [id, patch.name ?? null, patch.role ?? null, patch.active ?? null, patch.callAheadMinutes ?? null, bumpTokenVersion, now],
    );
    const s = rows[0];
    if (s && patch.active !== undefined) {
      // ق40 review (F2): every suspension interval is kept (events done during it are flagged later).
      if (s.active) {
        await q.query('UPDATE staff_suspensions SET reactivated_at = $2 WHERE staff_id = $1 AND reactivated_at IS NULL', [id, now]);
      } else if (s.suspended_at) {
        await q.query(
          'INSERT INTO staff_suspensions (staff_id, suspended_at) VALUES ($1, $2) ON CONFLICT (staff_id) WHERE reactivated_at IS NULL DO NOTHING',
          [id, s.suspended_at],
        );
      }
    }
    return s ?? null;
  },

  async recordLoginSuccess(q: TenantQueryable, id: string): Promise<void> {
    await q.query('UPDATE staff SET last_login_at = now(), failed_login_count = 0 WHERE id = $1', [id]);
  },

  async recordLoginFailure(q: TenantQueryable, id: string): Promise<void> {
    await q.query(
      'UPDATE staff SET failed_login_count = failed_login_count + 1, last_failed_login_at = now() WHERE id = $1',
      [id],
    );
  },

  async setPassword(q: TenantQueryable, id: string, passwordHash: string): Promise<void> {
    await q.query(
      `UPDATE staff SET password_hash = $2, token_version = token_version + 1, failed_login_count = 0, updated_at = now()
        WHERE id = $1`,
      [id, passwordHash],
    );
  },

  /** Counts active managers, locking their rows (serialises concurrent demotions — review L5). */
  async countActiveManagers(q: TenantQueryable): Promise<number> {
    const { rows } = await q.query<{ id: string }>("SELECT id FROM staff WHERE role = 'manager' AND active FOR UPDATE");
    return rows.length;
  },
};

import type { Queryable } from '../db/sql';

export type SalonStatus = 'pending_activation' | 'active' | 'suspended';

export interface SalonRecord {
  id: string;
  code: string;
  name: string;
  db_name: string;
  timezone: string;
  currency: string;
  status: SalonStatus;
  registered_at: Date;
  activated_at: Date | null;
  suspended_at: Date | null;
  schema_version: number;
}

const COLS = 'id, code, name, db_name, timezone, currency, status, registered_at, activated_at, suspended_at, schema_version';

/** Queries on the directory database (`salons`). Stateless; the caller passes the connection. */
export const DirectoryRepo = {
  async findByCode(q: Queryable, code: string): Promise<SalonRecord | null> {
    const { rows } = await q.query<SalonRecord>(`SELECT ${COLS} FROM salons WHERE code = $1`, [code]);
    return rows[0] ?? null;
  },

  async findById(q: Queryable, id: string): Promise<SalonRecord | null> {
    const { rows } = await q.query<SalonRecord>(`SELECT ${COLS} FROM salons WHERE id = $1`, [id]);
    return rows[0] ?? null;
  },

  /** Inserts a pending salon; returns null when the code or db name is already taken. */
  async insertPending(
    q: Queryable,
    s: { code: string; name: string; dbName: string; timezone: string; currency: string },
  ): Promise<SalonRecord | null> {
    const { rows } = await q.query<SalonRecord>(
      `INSERT INTO salons (code, name, db_name, timezone, currency)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT DO NOTHING
       RETURNING ${COLS}`,
      [s.code, s.name, s.dbName, s.timezone, s.currency],
    );
    return rows[0] ?? null;
  },

  async delete(q: Queryable, id: string): Promise<void> {
    await q.query('DELETE FROM salons WHERE id = $1', [id]);
  },

  async setSchemaVersion(q: Queryable, id: string, version: number): Promise<void> {
    await q.query('UPDATE salons SET schema_version = $2, updated_at = now() WHERE id = $1', [id, version]);
  },

  async setStatus(q: Queryable, id: string, status: SalonStatus): Promise<SalonRecord | null> {
    const { rows } = await q.query<SalonRecord>(
      `UPDATE salons SET status = $2::text,
         activated_at = CASE WHEN $2::text = 'active' THEN COALESCE(activated_at, now()) ELSE activated_at END,
         suspended_at = CASE WHEN $2::text = 'suspended' THEN now() ELSE NULL END,
         updated_at = now()
       WHERE id = $1 RETURNING ${COLS}`,
      [id, status],
    );
    return rows[0] ?? null;
  },

  async countPending(q: Queryable): Promise<number> {
    const { rows } = await q.query<{ n: string }>("SELECT count(*) AS n FROM salons WHERE status = 'pending_activation'");
    return Number(rows[0]!.n);
  },

  /** Salons never activated, registered before `before` (review M4 cleanup). */
  async stalePending(q: Queryable, before: Date): Promise<SalonRecord[]> {
    const { rows } = await q.query<SalonRecord>(
      `SELECT ${COLS} FROM salons WHERE status = 'pending_activation' AND activated_at IS NULL AND registered_at < $1 ORDER BY registered_at`,
      [before],
    );
    return rows;
  },

  async list(q: Queryable, status?: SalonStatus): Promise<SalonRecord[]> {
    const { rows } = status
      ? await q.query<SalonRecord>(`SELECT ${COLS} FROM salons WHERE status = $1 ORDER BY registered_at`, [status])
      : await q.query<SalonRecord>(`SELECT ${COLS} FROM salons ORDER BY registered_at`);
    return rows;
  },
};

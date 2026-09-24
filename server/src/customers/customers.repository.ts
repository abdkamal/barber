import type { TenantQueryable } from '../tenancy/tenant-context';

export type CustomerStatus = 'pending' | 'active' | 'suspended';

export interface CustomerRow {
  id: string;
  name: string;
  phone: string;
  password_hash: string | null;
  status: CustomerStatus;
  no_show_count: number;
  linked_walk_in_id: string | null;
  token_version: number;
  created_at: Date;
  last_login_at: Date | null;
}

export type CustomerPublic = Omit<CustomerRow, 'password_hash' | 'token_version'> & { is_walk_in: boolean };

const PUBLIC_COLS =
  'id, name, phone, status, no_show_count, linked_walk_in_id, created_at, last_login_at, (password_hash IS NULL) AS is_walk_in';

/** Customer queries. `q` must be a tenant-bound handle. */
export const CustomersRepo = {
  /** App account (has a password) with this phone. */
  async findAccountByPhone(q: TenantQueryable, phone: string): Promise<CustomerRow | null> {
    const { rows } = await q.query<CustomerRow>(
      'SELECT * FROM customers WHERE phone = $1 AND password_hash IS NOT NULL',
      [phone],
    );
    return rows[0] ?? null;
  },

  async findAccountById(q: TenantQueryable, id: string): Promise<CustomerRow | null> {
    const { rows } = await q.query<CustomerRow>('SELECT * FROM customers WHERE id = $1 AND password_hash IS NOT NULL', [id]);
    return rows[0] ?? null;
  },

  async findPublicById(q: TenantQueryable, id: string): Promise<CustomerPublic | null> {
    const { rows } = await q.query<CustomerPublic>(`SELECT ${PUBLIC_COLS} FROM customers WHERE id = $1`, [id]);
    return rows[0] ?? null;
  },

  /** Oldest unlinked walk-in record with this phone (ق14، ق20). */
  async findUnlinkedWalkIn(q: TenantQueryable, phone: string): Promise<{ id: string } | null> {
    const { rows } = await q.query<{ id: string }>(
      `SELECT c.id FROM customers c
        WHERE c.phone = $1 AND c.password_hash IS NULL
          AND NOT EXISTS (SELECT 1 FROM customers a WHERE a.linked_walk_in_id = c.id)
        ORDER BY c.created_at LIMIT 1`,
      [phone],
    );
    return rows[0] ?? null;
  },

  async insertAccount(
    q: TenantQueryable,
    c: { name: string; phone: string; passwordHash: string; status: CustomerStatus; linkedWalkInId: string | null },
  ): Promise<CustomerRow> {
    const { rows } = await q.query<CustomerRow>(
      `INSERT INTO customers (name, phone, password_hash, status, linked_walk_in_id)
       VALUES ($1, $2, $3, $4, $5) RETURNING *`,
      [c.name, c.phone, c.passwordHash, c.status, c.linkedWalkInId],
    );
    return rows[0]!;
  },

  async list(q: TenantQueryable, status?: CustomerStatus, limit = 100, offset = 0): Promise<CustomerPublic[]> {
    const { rows } = await q.query<CustomerPublic>(
      `SELECT ${PUBLIC_COLS} FROM customers
        WHERE password_hash IS NOT NULL AND ($1::text IS NULL OR status = $1)
        ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
      [status ?? null, limit, offset],
    );
    return rows;
  },

  async setStatus(q: TenantQueryable, id: string, status: CustomerStatus, bumpTokenVersion: boolean): Promise<CustomerPublic | null> {
    const { rows } = await q.query<CustomerPublic>(
      `UPDATE customers SET status = $2,
          token_version = token_version + CASE WHEN $3 THEN 1 ELSE 0 END, updated_at = now()
        WHERE id = $1 AND password_hash IS NOT NULL RETURNING ${PUBLIC_COLS}`,
      [id, status, bumpTokenVersion],
    );
    return rows[0] ?? null;
  },

  async recordLoginSuccess(q: TenantQueryable, id: string): Promise<void> {
    await q.query('UPDATE customers SET last_login_at = now(), failed_login_count = 0 WHERE id = $1', [id]);
  },

  async recordLoginFailure(q: TenantQueryable, id: string): Promise<void> {
    await q.query(
      'UPDATE customers SET failed_login_count = failed_login_count + 1, last_failed_login_at = now() WHERE id = $1',
      [id],
    );
  },

  async setPassword(q: TenantQueryable, id: string, passwordHash: string): Promise<void> {
    await q.query(
      `UPDATE customers SET password_hash = $2, token_version = token_version + 1, failed_login_count = 0, updated_at = now()
        WHERE id = $1`,
      [id, passwordHash],
    );
  },
};

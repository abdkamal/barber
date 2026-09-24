import type { TenantQueryable } from '../tenancy/tenant-context';

export interface ServiceRow {
  id: string;
  name: string;
  base_duration_minutes: number;
  price_minor: string; // bigint comes back as string from pg
  active: boolean;
  position: number;
  created_at: Date;
  updated_at: Date;
}

export const ServicesRepo = {
  async list(q: TenantQueryable): Promise<ServiceRow[]> {
    const { rows } = await q.query<ServiceRow>('SELECT * FROM services ORDER BY position, name');
    return rows;
  },

  async findById(q: TenantQueryable, id: string): Promise<ServiceRow | null> {
    const { rows } = await q.query<ServiceRow>('SELECT * FROM services WHERE id = $1', [id]);
    return rows[0] ?? null;
  },

  async insert(q: TenantQueryable, s: { name: string; durationMinutes: number; priceMinor: number; position?: number }): Promise<ServiceRow> {
    const { rows } = await q.query<ServiceRow>(
      `INSERT INTO services (name, base_duration_minutes, price_minor, position)
       VALUES ($1, $2, $3, COALESCE($4, 0)) RETURNING *`,
      [s.name, s.durationMinutes, s.priceMinor, s.position ?? null],
    );
    return rows[0]!;
  },

  async update(
    q: TenantQueryable,
    id: string,
    patch: { name?: string; durationMinutes?: number; priceMinor?: number; active?: boolean; position?: number },
  ): Promise<ServiceRow | null> {
    const { rows } = await q.query<ServiceRow>(
      `UPDATE services SET
         name = COALESCE($2, name),
         base_duration_minutes = COALESCE($3, base_duration_minutes),
         price_minor = COALESCE($4, price_minor),
         active = COALESCE($5, active),
         position = COALESCE($6, position),
         updated_at = now()
       WHERE id = $1 RETURNING *`,
      [id, patch.name ?? null, patch.durationMinutes ?? null, patch.priceMinor ?? null, patch.active ?? null, patch.position ?? null],
    );
    return rows[0] ?? null;
  },

  /** Hard delete; the caller must catch a foreign-key violation (bookings/catalog reference it) and suggest deactivating instead. */
  async delete(q: TenantQueryable, id: string): Promise<boolean> {
    const { rowCount } = await q.query('DELETE FROM services WHERE id = $1', [id]);
    return (rowCount ?? 0) > 0;
  },
};

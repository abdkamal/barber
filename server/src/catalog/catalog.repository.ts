import type { TenantQueryable } from '../tenancy/tenant-context';

export type CatalogKind = 'service' | 'product';

export interface CatalogItemRow {
  id: string;
  kind: CatalogKind;
  name: string;
  description: string | null;
  features: string[];
  price_minor: string | null;
  photo_path: string | null;
  position: number;
  visible: boolean;
  service_id: string | null;
  created_at: Date;
  updated_at: Date;
}

export const CatalogRepo = {
  async list(q: TenantQueryable): Promise<CatalogItemRow[]> {
    const { rows } = await q.query<CatalogItemRow>('SELECT * FROM catalog_items ORDER BY kind, position, name');
    return rows;
  },

  async findById(q: TenantQueryable, id: string): Promise<CatalogItemRow | null> {
    const { rows } = await q.query<CatalogItemRow>('SELECT * FROM catalog_items WHERE id = $1', [id]);
    return rows[0] ?? null;
  },

  async insert(
    q: TenantQueryable,
    it: {
      kind: CatalogKind;
      name: string;
      description: string | null;
      features: string[];
      priceMinor: number | null;
      position: number;
      visible: boolean;
      serviceId: string | null;
    },
  ): Promise<CatalogItemRow> {
    const { rows } = await q.query<CatalogItemRow>(
      `INSERT INTO catalog_items (kind, name, description, features, price_minor, position, visible, service_id)
       VALUES ($1, $2, $3, $4::jsonb, $5, $6, $7, $8) RETURNING *`,
      [it.kind, it.name, it.description, JSON.stringify(it.features), it.priceMinor, it.position, it.visible, it.serviceId],
    );
    return rows[0]!;
  },

  async update(
    q: TenantQueryable,
    id: string,
    patch: Partial<{
      name: string;
      description: string | null;
      features: string[];
      priceMinor: number | null;
      position: number;
      visible: boolean;
      photoPath: string | null;
    }>,
  ): Promise<CatalogItemRow | null> {
    const { rows } = await q.query<CatalogItemRow>(
      `UPDATE catalog_items SET
         name        = COALESCE($2, name),
         description = CASE WHEN $3::boolean THEN $4 ELSE description END,
         features    = CASE WHEN $5::boolean THEN $6::jsonb ELSE features END,
         price_minor = CASE WHEN $7::boolean THEN $8 ELSE price_minor END,
         position    = COALESCE($9, position),
         visible     = COALESCE($10, visible),
         photo_path  = CASE WHEN $11::boolean THEN $12 ELSE photo_path END,
         updated_at  = now()
       WHERE id = $1 RETURNING *`,
      [
        id,
        patch.name ?? null,
        'description' in patch, patch.description ?? null,
        'features' in patch, JSON.stringify(patch.features ?? []),
        'priceMinor' in patch, patch.priceMinor ?? null,
        patch.position ?? null,
        patch.visible ?? null,
        'photoPath' in patch, patch.photoPath ?? null,
      ],
    );
    return rows[0] ?? null;
  },

  async delete(q: TenantQueryable, id: string): Promise<CatalogItemRow | null> {
    const { rows } = await q.query<CatalogItemRow>('DELETE FROM catalog_items WHERE id = $1 RETURNING *', [id]);
    return rows[0] ?? null;
  },
};

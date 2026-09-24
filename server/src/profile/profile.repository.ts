import type { TenantQueryable } from '../tenancy/tenant-context';

export interface SocialLink {
  platform: string;
  url: string;
}

export interface SalonProfileRow {
  name: string;
  about: string | null;
  logo_path: string | null;
  address: string | null;
  latitude: number | null;
  longitude: number | null;
  phone: string | null;
  whatsapp: string | null;
  social_links: SocialLink[];
  updated_at: Date;
}

export interface SalonPhotoRow {
  id: string;
  path: string;
  position: number;
  created_at: Date;
}

export const ProfileRepo = {
  async get(q: TenantQueryable): Promise<SalonProfileRow> {
    const { rows } = await q.query<SalonProfileRow>(
      `SELECT name, about, logo_path, address, latitude::float8 AS latitude, longitude::float8 AS longitude,
              phone, whatsapp, social_links, updated_at
         FROM salon_profile WHERE id = 1`,
    );
    return rows[0]!;
  },

  async update(
    q: TenantQueryable,
    patch: Partial<{
      name: string;
      about: string | null;
      address: string | null;
      latitude: number | null;
      longitude: number | null;
      phone: string | null;
      whatsapp: string | null;
      socialLinks: SocialLink[];
    }>,
  ): Promise<SalonProfileRow> {
    const { rows } = await q.query<SalonProfileRow>(
      `UPDATE salon_profile SET
         name         = COALESCE($1, name),
         about        = CASE WHEN $2::boolean THEN $3 ELSE about END,
         address      = CASE WHEN $4::boolean THEN $5 ELSE address END,
         latitude     = CASE WHEN $6::boolean THEN $7 ELSE latitude END,
         longitude    = CASE WHEN $6::boolean THEN $8 ELSE longitude END,
         phone        = CASE WHEN $9::boolean THEN $10 ELSE phone END,
         whatsapp     = CASE WHEN $11::boolean THEN $12 ELSE whatsapp END,
         social_links = CASE WHEN $13::boolean THEN $14::jsonb ELSE social_links END,
         updated_at   = now()
       WHERE id = 1
       RETURNING name, about, logo_path, address, latitude::float8 AS latitude, longitude::float8 AS longitude,
                 phone, whatsapp, social_links, updated_at`,
      [
        patch.name ?? null,
        'about' in patch, patch.about ?? null,
        'address' in patch, patch.address ?? null,
        'latitude' in patch, patch.latitude ?? null, patch.longitude ?? null,
        'phone' in patch, patch.phone ?? null,
        'whatsapp' in patch, patch.whatsapp ?? null,
        'socialLinks' in patch, JSON.stringify(patch.socialLinks ?? []),
      ],
    );
    return rows[0]!;
  },

  async setLogo(q: TenantQueryable, logoPath: string | null): Promise<{ logo_path: string | null } | null> {
    const { rows } = await q.query<{ logo_path: string | null }>(
      'UPDATE salon_profile SET logo_path = $1, updated_at = now() WHERE id = 1 RETURNING logo_path',
      [logoPath],
    );
    return rows[0] ?? null;
  },
};

export const PhotosRepo = {
  async list(q: TenantQueryable): Promise<SalonPhotoRow[]> {
    const { rows } = await q.query<SalonPhotoRow>('SELECT id, path, position, created_at FROM salon_photos ORDER BY position');
    return rows;
  },

  /** Lowest free slot in 1..6, or null when all 6 are taken. Locks existing rows to avoid a race between two uploads. */
  async nextFreePosition(q: TenantQueryable): Promise<number | null> {
    const { rows } = await q.query<{ position: number }>('SELECT position FROM salon_photos ORDER BY position FOR UPDATE');
    const taken = new Set(rows.map((r) => r.position));
    for (let p = 1; p <= 6; p++) if (!taken.has(p)) return p;
    return null;
  },

  async insert(q: TenantQueryable, path: string, position: number): Promise<SalonPhotoRow> {
    const { rows } = await q.query<SalonPhotoRow>(
      'INSERT INTO salon_photos (path, position) VALUES ($1, $2) RETURNING id, path, position, created_at',
      [path, position],
    );
    return rows[0]!;
  },

  async findById(q: TenantQueryable, id: string): Promise<SalonPhotoRow | null> {
    const { rows } = await q.query<SalonPhotoRow>('SELECT id, path, position, created_at FROM salon_photos WHERE id = $1', [id]);
    return rows[0] ?? null;
  },

  async deleteById(q: TenantQueryable, id: string): Promise<SalonPhotoRow | null> {
    const { rows } = await q.query<SalonPhotoRow>('DELETE FROM salon_photos WHERE id = $1 RETURNING id, path, position, created_at', [id]);
    return rows[0] ?? null;
  },
};

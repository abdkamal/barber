import { Inject, Injectable } from '@nestjs/common';
import type { Pool } from 'pg';
import { APP_CONFIG, AppConfig } from '../config/config';
import { PoolManager } from '../db/pools';
import { DirectoryRepo, SalonRecord } from '../directory/directory.repository';
import { TENANT_MINT_KEY, TenantContext, TenantSalon } from './tenant-context';

/**
 * Resolves salons from the directory and mints TenantContexts.
 *  - fromVerifiedToken(): the ONLY way authenticated requests get a tenant (salon id from the JWT).
 *  - forCode(): used solely by the unauthenticated entry points (login / register / public profile)
 *    where the salon code is, by definition, user input.
 * On first use of a salon database the server verifies that the database really belongs to that
 * salon (salon_meta), guarding against a corrupted directory mapping.
 */
@Injectable()
export class TenantResolver {
  private readonly cache = new Map<string, { record: SalonRecord; expires: number }>();
  private readonly verifiedDbs = new Map<string, string>(); // dbName → salonId

  constructor(
    @Inject(APP_CONFIG) private readonly config: AppConfig,
    private readonly pools: PoolManager,
  ) {}

  async salonById(id: string): Promise<SalonRecord | null> {
    const now = Date.now();
    const hit = this.cache.get(id);
    if (hit && hit.expires > now) return hit.record;
    const rec = await DirectoryRepo.findById(this.pools.directoryPool(), id);
    if (rec) this.cache.set(id, { record: rec, expires: now + this.config.db.directoryCacheTtlMs });
    else this.cache.delete(id);
    return rec;
  }

  async salonByCode(code: string): Promise<SalonRecord | null> {
    return DirectoryRepo.findByCode(this.pools.directoryPool(), code);
  }

  invalidate(id: string): void {
    this.cache.delete(id);
  }

  /** Salon id MUST come from a verified token. Returns null for unknown / unprovisioned salons. */
  async fromVerifiedToken(salonId: string): Promise<TenantContext | null> {
    const rec = await this.salonById(salonId);
    return rec ? this.contextFor(rec) : null;
  }

  async forCode(code: string): Promise<{ record: SalonRecord; tenant: TenantContext } | null> {
    const rec = await this.salonByCode(code);
    const tenant = rec ? this.contextFor(rec) : null;
    return rec && tenant ? { record: rec, tenant } : null;
  }

  contextFor(rec: SalonRecord): TenantContext | null {
    if (rec.schema_version <= 0) return null; // still being provisioned
    const salon: TenantSalon = {
      id: rec.id,
      code: rec.code,
      name: rec.name,
      dbName: rec.db_name,
      status: rec.status,
      timezone: rec.timezone,
      currency: rec.currency,
    };
    return TenantContext.mint(TENANT_MINT_KEY, salon, () => this.verifiedPool(rec));
  }

  private async verifiedPool(rec: SalonRecord): Promise<Pool> {
    const pool = this.pools.tenantPool(rec.db_name);
    if (this.verifiedDbs.get(rec.db_name) === rec.id) return pool;
    const { rows } = await pool.query<{ salon_id: string }>('SELECT salon_id FROM salon_meta WHERE id = 1');
    if (rows[0]?.salon_id !== rec.id) {
      throw new Error(`Tenant database identity mismatch for salon ${rec.code}`);
    }
    this.verifiedDbs.set(rec.db_name, rec.id);
    return pool;
  }
}

import { Inject, Injectable, Logger } from '@nestjs/common';
import { APP_CONFIG, AppConfig } from '../config/config';
import { Errors } from '../common/errors';
import { normalizeUsername, USERNAME_RE } from '../common/normalize';
import { migrateSalon } from '../db/migrate-all';
import { PoolManager } from '../db/pools';
import { quoteIdent } from '../db/sql';
import { DirectoryRepo, SalonRecord } from '../directory/directory.repository';
import { salonCodeCandidate, salonDbName } from '../directory/salon-code';
import { PasswordHasher, passwordPolicyError } from '../auth/passwords';
import { writeAudit } from '../security/audit';
import { StaffRepo } from '../staff/staff.repository';
import { TenantResolver } from '../tenancy/tenant-resolver.service';

export interface RegisterSalonInput {
  salon: { name: string; timezone: string; currency: string; phone?: string; address?: string; about?: string };
  owner: { name: string; username: string; password: string };
}

export function isValidTimezone(tz: string): boolean {
  try {
    new Intl.DateTimeFormat('en', { timeZone: tz });
    return tz.length <= 64;
  } catch {
    return false;
  }
}

export function isValidCurrency(c: string): boolean {
  return /^[A-Z]{3}$/.test(c) && (Intl.supportedValuesOf?.('currency') ?? [c]).includes(c);
}

const MAX_CODE_ATTEMPTS = 25;

/**
 * Self-registration of a salon (ق37): creates the directory row (pending_activation), a dedicated
 * database, migrates it, and creates the owner as the first manager. On any failure everything
 * created so far is removed again.
 */
@Injectable()
export class ProvisioningService {
  private readonly logger = new Logger('Provisioning');

  constructor(
    @Inject(APP_CONFIG) private readonly config: AppConfig,
    private readonly pools: PoolManager,
    private readonly resolver: TenantResolver,
    private readonly hasher: PasswordHasher,
  ) {}

  async register(input: RegisterSalonInput, ip: string | null): Promise<SalonRecord> {
    const username = normalizeUsername(input.owner.username);
    if (!USERNAME_RE.test(username)) throw Errors.validation([{ path: 'owner.username', code: 'invalid_username' }]);
    const min = passwordPolicyError('staff', input.owner.password);
    if (min !== null) throw Errors.weakPassword(min);
    if (!isValidTimezone(input.salon.timezone)) throw Errors.validation([{ path: 'salon.timezone', code: 'invalid_timezone' }]);
    const currency = input.salon.currency.toUpperCase();
    if (!isValidCurrency(currency)) throw Errors.validation([{ path: 'salon.currency', code: 'invalid_currency' }]);
    const passwordHash = await this.hasher.hash(input.owner.password);
    const name = input.salon.name.trim();

    // 1. Reserve a unique code in the directory (retry on collision).
    let record: SalonRecord | null = null;
    for (let attempt = 0; attempt < MAX_CODE_ATTEMPTS && !record; attempt++) {
      const code = salonCodeCandidate(name, attempt);
      record = await DirectoryRepo.insertPending(this.pools.directoryPool(), {
        code,
        name,
        dbName: salonDbName(this.config.db.salonDbPrefix, code),
        timezone: input.salon.timezone,
        currency,
      });
    }
    if (!record) throw Errors.conflict('SALON_CODE_EXHAUSTED', 'تعذر توليد رمز للصالون، حاول باسم مختلف');

    let dbCreated = false;
    try {
      // 2. Dedicated database (direct admin connection; CREATE DATABASE cannot run in a transaction).
      const admin = await this.pools.adminClient();
      try {
        await admin.query(`CREATE DATABASE ${quoteIdent(record.db_name)} TEMPLATE template0 ENCODING 'UTF8'`);
        dbCreated = true;
      } finally {
        await admin.end();
      }
      // 3. Schema + identity row.
      const mig = await migrateSalon(this.pools, this.config, record);
      const c = await this.pools.adminClient(record.db_name);
      try {
        await c.query('INSERT INTO salon_meta (salon_id, salon_code) VALUES ($1, $2)', [record.id, record.code]);
      } finally {
        await c.end();
      }
      record = { ...record, schema_version: mig.to };

      // 4. Profile + first manager through the normal tenant-bound handle.
      const tenant = this.resolver.contextFor(record);
      if (!tenant) throw new Error('tenant not available after provisioning');
      const rec = record;
      await tenant.db.tx(async (q) => {
        await q.query('INSERT INTO salon_profile (name, phone, address, about) VALUES ($1, $2, $3, $4)', [
          name,
          input.salon.phone ?? null,
          input.salon.address ?? null,
          input.salon.about ?? null,
        ]);
        const owner = await StaffRepo.insert(q, { name: input.owner.name.trim(), username, passwordHash, role: 'manager' });
        await writeAudit(q, {
          actorKind: 'staff',
          actorId: owner.id,
          action: 'salon.registered',
          targetKind: 'salon',
          targetId: rec.id,
          ip,
          details: { code: rec.code },
        });
      });
      this.logger.log(`Salon registered: ${record.code} (pending activation)`);
      return record;
    } catch (e) {
      this.logger.error(`Provisioning failed for ${record.code}: ${(e as Error).message}`);
      await this.rollback(record, dbCreated);
      throw e;
    }
  }

  private async rollback(record: SalonRecord, dbCreated: boolean): Promise<void> {
    try {
      if (dbCreated) {
        const admin = await this.pools.adminClient();
        try {
          await admin.query(`DROP DATABASE IF EXISTS ${quoteIdent(record.db_name)} WITH (FORCE)`);
        } finally {
          await admin.end();
        }
      }
      await DirectoryRepo.delete(this.pools.directoryPool(), record.id);
    } catch (e) {
      this.logger.error(`Rollback failed for ${record.code}: ${(e as Error).message}`);
    }
  }
}

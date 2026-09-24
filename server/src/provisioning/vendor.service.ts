import { PasswordResetService } from '../auth/password-reset.service';
import { PasswordHasher } from '../auth/passwords';
import { LoginThrottle } from '../auth/login-throttle';
import type { AppConfig } from '../config/config';
import { normalizeSalonCode, normalizeUsername } from '../common/normalize';
import { PoolManager } from '../db/pools';
import { DirectoryRepo, SalonRecord, SalonStatus } from '../directory/directory.repository';
import { writeAudit } from '../security/audit';
import { StaffRepo } from '../staff/staff.repository';
import { TenantResolver } from '../tenancy/tenant-resolver.service';

export class VendorError extends Error {}

/**
 * System-vendor operations (design §1: command-line tools in v1):
 * list salons, activate / suspend, and reset a salon manager's password via a one-time code.
 */
export class VendorService {
  private readonly resolver: TenantResolver;
  private readonly resets: PasswordResetService;

  constructor(
    config: AppConfig,
    private readonly pools: PoolManager,
  ) {
    this.resolver = new TenantResolver(config, pools);
    this.resets = new PasswordResetService(config, this.resolver, new PasswordHasher(config.auth.argon2), new LoginThrottle(config.backoff));
  }

  list(status?: SalonStatus): Promise<SalonRecord[]> {
    return DirectoryRepo.list(this.pools.directoryPool(), status);
  }

  private async salon(rawCode: string): Promise<SalonRecord> {
    const rec = await DirectoryRepo.findByCode(this.pools.directoryPool(), normalizeSalonCode(rawCode));
    if (!rec) throw new VendorError(`No salon with code ${rawCode}`);
    return rec;
  }

  private async setStatus(rawCode: string, status: SalonStatus, action: string): Promise<SalonRecord> {
    const rec = await this.salon(rawCode);
    if (rec.schema_version <= 0) throw new VendorError(`Salon ${rec.code} is not fully provisioned`);
    const updated = (await DirectoryRepo.setStatus(this.pools.directoryPool(), rec.id, status))!;
    const t = this.resolver.contextFor(updated);
    if (t) await writeAudit(t, { actorKind: 'vendor', action, targetKind: 'salon', targetId: rec.id, details: { from: rec.status, to: status } });
    return updated;
  }

  activate(code: string): Promise<SalonRecord> {
    return this.setStatus(code, 'active', 'salon.activated');
  }

  suspend(code: string): Promise<SalonRecord> {
    return this.setStatus(code, 'suspended', 'salon.suspended');
  }

  /** Issues a one-time reset code for a manager of the salon (the only way a manager password is reset). */
  async resetManagerPassword(rawCode: string, username?: string): Promise<{ salon: string; username: string; code: string; expiresAt: Date }> {
    const rec = await this.salon(rawCode);
    const t = this.resolver.contextFor(rec);
    if (!t) throw new VendorError(`Salon ${rec.code} is not fully provisioned`);
    let target;
    if (username) {
      target = await StaffRepo.findByUsername(t.db, normalizeUsername(username));
      if (!target || target.role !== 'manager') throw new VendorError(`No manager "${username}" in ${rec.code}`);
    } else {
      const managers = (await StaffRepo.list(t.db)).filter((s) => s.role === 'manager');
      if (managers.length !== 1) {
        throw new VendorError(
          `${rec.code} has ${managers.length} managers; pass --username (${managers.map((m) => m.username).join(', ')})`,
        );
      }
      target = managers[0]!;
    }
    const r = await this.resets.issue(t, { kind: 'staff', id: target.id }, { kind: 'vendor' }, null);
    return { salon: rec.code, username: target.username, code: r.code, expiresAt: r.expiresAt };
  }
}

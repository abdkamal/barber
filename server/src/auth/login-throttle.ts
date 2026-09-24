import type { AppConfig } from '../config/config';
import type { TenantContext } from '../tenancy/tenant-context';
import { backoffDelayMs } from './backoff';

export type ThrottleScope = 'staff_login' | 'customer_login' | 'password_reset';

/**
 * Progressive backoff stored in the salon DB, keyed by (scope, account identifier, IP) plus an
 * IP-wide row (identifier '*') with a higher free allowance. Deliberately NOT keyed by account
 * alone: that would let anyone slow down a barber's own device (the reason ق31 replaced lockout).
 */
export class LoginThrottle {
  constructor(private readonly cfg: AppConfig['backoff']) {}

  /** Seconds until the next attempt is allowed (0 = allowed now). */
  async retryAfterSec(t: TenantContext, scope: ThrottleScope, identifier: string, ip: string): Promise<number> {
    const { rows } = await t.db.query<{ wait_ms: string }>(
      `SELECT GREATEST(0, EXTRACT(EPOCH FROM (next_allowed_at - now())) * 1000)::bigint AS wait_ms
         FROM login_throttle
        WHERE scope = $1 AND ip = $3 AND identifier IN ($2, '*')
          AND updated_at > now() - make_interval(secs => $4::double precision / 1000)`,
      [scope, identifier, ip, this.cfg.resetAfterMs],
    );
    const wait = Math.max(0, ...rows.map((r) => Number(r.wait_ms)));
    return Math.ceil(wait / 1000);
  }

  async recordFailure(t: TenantContext, scope: ThrottleScope, identifier: string, ip: string): Promise<void> {
    await this.bump(t, scope, identifier, ip, this.cfg.freeAttempts);
    await this.bump(t, scope, '*', ip, this.cfg.ipFreeAttempts);
  }

  /** A success clears the account+IP row (the IP-wide row decays with time only). */
  async recordSuccess(t: TenantContext, scope: ThrottleScope, identifier: string, ip: string): Promise<void> {
    await t.db.query('DELETE FROM login_throttle WHERE scope = $1 AND identifier = $2 AND ip = $3', [scope, identifier, ip]);
  }

  private async bump(t: TenantContext, scope: ThrottleScope, identifier: string, ip: string, free: number): Promise<void> {
    await t.db.tx(async (q) => {
      const { rows } = await q.query<{ failures: number }>(
        `INSERT INTO login_throttle (scope, identifier, ip, failures, updated_at)
         VALUES ($1, $2, $3, 1, now())
         ON CONFLICT (scope, identifier, ip) DO UPDATE SET
           failures = CASE WHEN login_throttle.updated_at < now() - make_interval(secs => $4::double precision / 1000)
                           THEN 1 ELSE login_throttle.failures + 1 END,
           updated_at = now()
         RETURNING failures`,
        [scope, identifier, ip, this.cfg.resetAfterMs],
      );
      const failures = rows[0]!.failures;
      const delay = backoffDelayMs(failures, { free, baseMs: this.cfg.baseMs, maxMs: this.cfg.maxMs });
      await q.query(
        `UPDATE login_throttle SET next_allowed_at = now() + make_interval(secs => $4::double precision / 1000)
          WHERE scope = $1 AND identifier = $2 AND ip = $3`,
        [scope, identifier, ip, delay],
      );
    });
  }
}

import { Inject, Injectable } from '@nestjs/common';
import { APP_CONFIG, AppConfig } from '../config/config';
import { Errors } from '../common/errors';
import { normalizePhone, normalizeSalonCode, normalizeUsername, SALON_CODE_RE, USERNAME_RE } from '../common/normalize';
import { CustomersRepo } from '../customers/customers.repository';
import { writeAudit } from '../security/audit';
import { StaffRepo } from '../staff/staff.repository';
import { TenantContext, TenantQueryable } from '../tenancy/tenant-context';
import { TenantResolver } from '../tenancy/tenant-resolver.service';
import { LoginThrottle } from './login-throttle';
import { PasswordHasher, passwordPolicyError } from './passwords';
import type { SubjectKind } from './principal';
import { generateResetCode, hashResetCode, ResetCodesRepo, resetCodeMatches } from './reset-codes';
import { SessionsRepo } from './sessions';

export type ResetIssuer = { kind: 'staff'; staffId: string } | { kind: 'vendor' };

/**
 * One-time password reset codes (design §7): issued by a manager (for barbers/customers) or by the
 * vendor (for managers); valid 24 h, stored as an HMAC, single use, max 5 wrong tries; redeeming one
 * sets a new password and revokes every session of the account.
 */
@Injectable()
export class PasswordResetService {
  constructor(
    @Inject(APP_CONFIG) private readonly config: AppConfig,
    private readonly resolver: TenantResolver,
    private readonly hasher: PasswordHasher,
    private readonly throttle: LoginThrottle,
  ) {}

  /** Returns the plaintext code exactly once; only its HMAC is stored. */
  async issue(
    t: TenantContext,
    subject: { kind: SubjectKind; id: string },
    issuer: ResetIssuer,
    ip: string | null,
    q?: TenantQueryable,
  ): Promise<{ code: string; expiresAt: Date }> {
    const code = generateResetCode();
    const run = async (tx: TenantQueryable) => {
      const r = await ResetCodesRepo.issue(tx, {
        subjectKind: subject.kind,
        subjectId: subject.id,
        codeHash: hashResetCode(this.config.auth.resetCodePepper, t.salonId, code),
        ttlHours: this.config.auth.resetCodeTtlHours,
        issuedBy: issuer,
      });
      await writeAudit(tx, {
        actorKind: issuer.kind,
        actorId: issuer.kind === 'staff' ? issuer.staffId : null,
        action: 'reset_code.issued',
        targetKind: subject.kind,
        targetId: subject.id,
        ip,
      });
      return { code, expiresAt: r.expires_at };
    };
    return q ? run(q) : t.db.tx(run);
  }

  async redeem(dto: { salonCode: string; identifier: string; code: string; newPassword: string }, ip: string): Promise<void> {
    const code = normalizeSalonCode(dto.salonCode);
    const found = SALON_CODE_RE.test(code) ? await this.resolver.forCode(code) : null;
    if (!found || found.record.status === 'suspended') throw Errors.invalidResetCode();
    const t = found.tenant;
    const identifier = dto.identifier.trim();
    // Review M1: one throttle key per account, however the phone/username was typed.
    const throttleKey = normalizePhone(identifier) ?? normalizeUsername(identifier);

    const wait = await this.throttle.retryAfterSec(t, 'password_reset', throttleKey, ip);
    if (wait > 0) throw Errors.loginBackoff(wait);
    await this.throttle.slowDown(t, 'password_reset', throttleKey);

    // The identifier is a staff username or a customer phone number.
    const candidates: Array<{ kind: SubjectKind; id: string }> = [];
    const username = normalizeUsername(identifier);
    if (USERNAME_RE.test(username)) {
      const s = await StaffRepo.findByUsername(t.db, username);
      if (s) candidates.push({ kind: 'staff', id: s.id });
    }
    const phone = normalizePhone(identifier);
    if (phone && found.record.status === 'active') {
      const c = await CustomersRepo.findAccountByPhone(t.db, phone);
      if (c) candidates.push({ kind: 'customer', id: c.id });
    }

    const pepper = this.config.auth.resetCodePepper;
    let match: { kind: SubjectKind; id: string; codeId: string } | null = null;
    const active: string[] = [];
    for (const cand of candidates) {
      const rc = await ResetCodesRepo.findActive(t.db, cand.kind, cand.id);
      if (!rc) continue;
      active.push(rc.id);
      if (resetCodeMatches(pepper, t.salonId, dto.code, rc.code_hash)) {
        match = { ...cand, codeId: rc.id };
        break;
      }
    }
    if (!match) {
      for (const id of active) await ResetCodesRepo.recordFailure(t.db, id);
      await this.throttle.recordFailure(t, 'password_reset', throttleKey, ip);
      throw Errors.invalidResetCode();
    }
    // Validate the new password BEFORE consuming the code, so a weak choice does not burn it.
    const min = passwordPolicyError(match.kind, dto.newPassword);
    if (min !== null) throw Errors.weakPassword(min);
    const hash = await this.hasher.hash(dto.newPassword);

    const m = match;
    await t.db.tx(async (q) => {
      const rc = await ResetCodesRepo.findActive(q, m.kind, m.id, true);
      if (!rc || rc.id !== m.codeId || !(await ResetCodesRepo.markUsed(q, rc.id))) throw Errors.invalidResetCode();
      if (m.kind === 'staff') await StaffRepo.setPassword(q, m.id, hash);
      else await CustomersRepo.setPassword(q, m.id, hash);
      const revoked = await SessionsRepo.revokeAllFor(q, m.kind, m.id, 'password_reset');
      await writeAudit(q, {
        actorKind: m.kind,
        actorId: m.id,
        action: 'password.reset_with_code',
        targetKind: m.kind,
        targetId: m.id,
        ip,
        details: { revokedSessions: revoked },
      });
    });
    await this.throttle.recordSuccess(t, 'password_reset', throttleKey, ip);
  }
}

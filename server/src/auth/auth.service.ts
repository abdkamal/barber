import { Inject, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { APP_CONFIG, AppConfig } from '../config/config';
import { Errors } from '../common/errors';
import { normalizePhone, normalizeSalonCode, normalizeUsername, SALON_CODE_RE, USERNAME_RE } from '../common/normalize';
import { isUniqueViolation } from '../db/sql';
import { CustomersRepo } from '../customers/customers.repository';
import { writeAudit } from '../security/audit';
import { SettingsRepo } from '../settings/settings.repository';
import { StaffRepo } from '../staff/staff.repository';
import { TenantContext, TenantQueryable } from '../tenancy/tenant-context';
import { TenantResolver } from '../tenancy/tenant-resolver.service';
import type { SalonRecord } from '../directory/directory.repository';
import { LoginThrottle, ThrottleScope } from './login-throttle';
import { PasswordHasher, passwordPolicyError } from './passwords';
import type { Principal, Role, SubjectKind } from './principal';
import { SessionsRepo } from './sessions';
import { sha256Hex, TokenService } from './tokens';

export interface SessionResponse {
  accessToken: string;
  accessTokenExpiresIn: number;
  refreshToken: string;
  role: Role;
  salon: { code: string; name: string; status: string; timezone: string; currency: string };
  account: { id: string; name: string; status?: string };
}

type Subject = { kind: SubjectKind; id: string; role: Role; tokenVersion: number; name: string; status?: string };

@Injectable()
export class AuthService {
  constructor(
    @Inject(APP_CONFIG) private readonly config: AppConfig,
    private readonly resolver: TenantResolver,
    private readonly hasher: PasswordHasher,
    private readonly tokens: TokenService,
    private readonly throttle: LoginThrottle,
  ) {}

  // ─── Sessions ─────────────────────────────────────────────────────────────────────

  private async createSession(t: TenantContext, q: TenantQueryable, s: Subject): Promise<SessionResponse> {
    const sessionId = await SessionsRepo.create(q, s.kind, s.id);
    const jti = randomUUID();
    const claims = { sid: t.salonId, sub: s.id, role: s.role, tv: s.tokenVersion, sess: sessionId };
    const refresh = this.tokens.signRefresh({ ...claims, jti });
    await SessionsRepo.addRefreshToken(q, { id: jti, sessionId, tokenHash: sha256Hex(refresh.token), expiresAt: refresh.expiresAt });
    return this.sessionResponse(t, s, this.tokens.signAccess(claims), refresh.token);
  }

  private sessionResponse(t: TenantContext, s: Subject, accessToken: string, refreshToken: string): SessionResponse {
    const { code, name, status, timezone, currency } = t.salon;
    return {
      accessToken,
      accessTokenExpiresIn: this.config.auth.accessTtlSec,
      refreshToken,
      role: s.role,
      salon: { code, name, status, timezone, currency },
      account: { id: s.id, name: s.name, ...(s.status ? { status: s.status } : {}) },
    };
  }

  private async resolveSalon(rawCode: string): Promise<{ record: SalonRecord; tenant: TenantContext } | null> {
    const code = normalizeSalonCode(rawCode);
    if (!SALON_CODE_RE.test(code)) return null;
    return this.resolver.forCode(code);
  }

  private async checkBackoff(t: TenantContext, scope: ThrottleScope, identifier: string, ip: string): Promise<void> {
    const wait = await this.throttle.retryAfterSec(t, scope, identifier, ip);
    if (wait > 0) throw Errors.loginBackoff(wait);
  }

  // ─── Staff ────────────────────────────────────────────────────────────────────────

  async staffLogin(dto: { salonCode: string; username: string; password: string }, ip: string): Promise<SessionResponse> {
    const found = await this.resolveSalon(dto.salonCode);
    const username = normalizeUsername(dto.username);
    if (!found || !USERNAME_RE.test(username)) {
      await this.hasher.verifyDummy(dto.password);
      throw Errors.invalidCredentials();
    }
    const { tenant: t, record } = found;
    await this.checkBackoff(t, 'staff_login', username, ip);

    const staff = await StaffRepo.findByUsername(t.db, username);
    const ok = staff ? await this.hasher.verify(staff.password_hash, dto.password) : await this.hasher.verifyDummy(dto.password);
    if (!staff || !ok) {
      await this.throttle.recordFailure(t, 'staff_login', username, ip);
      if (staff) await StaffRepo.recordLoginFailure(t.db, staff.id);
      await writeAudit(t, {
        actorKind: 'anonymous',
        action: 'staff.login_failed',
        targetKind: staff ? 'staff' : null,
        targetId: staff?.id ?? null,
        ip,
        details: staff ? {} : { username },
      });
      throw Errors.invalidCredentials();
    }
    await this.throttle.recordSuccess(t, 'staff_login', username, ip);
    if (record.status === 'suspended') throw Errors.salonSuspended();
    if (!staff.active) throw Errors.accountSuspended();

    return t.db.tx(async (q) => {
      await StaffRepo.recordLoginSuccess(q, staff.id);
      await writeAudit(q, { actorKind: 'staff', actorId: staff.id, action: 'staff.login', targetKind: 'staff', targetId: staff.id, ip });
      return this.createSession(t, q, {
        kind: 'staff',
        id: staff.id,
        role: staff.role,
        tokenVersion: staff.token_version,
        name: staff.name,
      });
    });
  }

  // ─── Customers ────────────────────────────────────────────────────────────────────

  /** Customers only ever see active salons (ق37). */
  private async resolveActiveSalonForCustomer(rawCode: string) {
    const found = await this.resolveSalon(rawCode);
    if (!found || found.record.status !== 'active') throw Errors.salonNotFound();
    return found.tenant;
  }

  async customerRegister(
    dto: { salonCode: string; name: string; phone: string; password: string },
    ip: string,
  ): Promise<SessionResponse> {
    const t = await this.resolveActiveSalonForCustomer(dto.salonCode);
    const phone = normalizePhone(dto.phone);
    if (!phone) throw Errors.validation([{ path: 'phone', code: 'invalid_phone' }]);
    const min = passwordPolicyError('customer', dto.password);
    if (min !== null) throw Errors.weakPassword(min);
    const passwordHash = await this.hasher.hash(dto.password);
    const settings = await SettingsRepo.get(t.db);

    try {
      return await t.db.tx(async (q) => {
        if (await CustomersRepo.findAccountByPhone(q, phone)) throw Errors.phoneTaken();
        // ق20: automatic linking to an earlier walk-in record only when manager approval is on
        // (the manager then confirms it while approving); otherwise staff link it manually later.
        const walkIn = settings.require_account_approval ? await CustomersRepo.findUnlinkedWalkIn(q, phone) : null;
        const status = settings.require_account_approval ? 'pending' : 'active';
        const c = await CustomersRepo.insertAccount(q, {
          name: dto.name.trim(),
          phone,
          passwordHash,
          status,
          linkedWalkInId: walkIn?.id ?? null,
        });
        await writeAudit(q, {
          actorKind: 'customer',
          actorId: c.id,
          action: 'customer.registered',
          targetKind: 'customer',
          targetId: c.id,
          ip,
          details: { status, linkedWalkInId: walkIn?.id ?? null },
        });
        return this.createSession(t, q, { kind: 'customer', id: c.id, role: 'customer', tokenVersion: c.token_version, name: c.name, status });
      });
    } catch (e) {
      if (isUniqueViolation(e, 'customers_account_phone_key')) throw Errors.phoneTaken();
      throw e;
    }
  }

  async customerLogin(dto: { salonCode: string; phone: string; password: string }, ip: string): Promise<SessionResponse> {
    const t = await this.resolveActiveSalonForCustomer(dto.salonCode);
    const phone = normalizePhone(dto.phone);
    if (!phone) {
      await this.hasher.verifyDummy(dto.password);
      throw Errors.invalidCredentials();
    }
    await this.checkBackoff(t, 'customer_login', phone, ip);
    const c = await CustomersRepo.findAccountByPhone(t.db, phone);
    const ok = c?.password_hash ? await this.hasher.verify(c.password_hash, dto.password) : await this.hasher.verifyDummy(dto.password);
    if (!c || !ok) {
      await this.throttle.recordFailure(t, 'customer_login', phone, ip);
      if (c) await CustomersRepo.recordLoginFailure(t.db, c.id);
      throw Errors.invalidCredentials();
    }
    await this.throttle.recordSuccess(t, 'customer_login', phone, ip);
    if (c.status === 'suspended') throw Errors.accountSuspended();
    return t.db.tx(async (q) => {
      await CustomersRepo.recordLoginSuccess(q, c.id);
      return this.createSession(t, q, { kind: 'customer', id: c.id, role: 'customer', tokenVersion: c.token_version, name: c.name, status: c.status });
    });
  }

  // ─── Refresh / logout ─────────────────────────────────────────────────────────────

  /**
   * Rotating refresh tokens. The salon comes from the signed refresh token (never from the body).
   * Presenting an already-rotated token revokes the whole session (family) — reuse detection.
   */
  async refresh(refreshToken: string, ip: string): Promise<SessionResponse> {
    const claims = this.tokens.verifyRefresh(refreshToken);
    if (!claims) throw Errors.invalidRefreshToken();
    const t = await this.resolver.fromVerifiedToken(claims.sid);
    if (!t || t.salon.status === 'suspended') throw Errors.invalidRefreshToken();
    if (claims.role === 'customer' && t.salon.status !== 'active') throw Errors.invalidRefreshToken();

    type Outcome = { ok: SessionResponse } | { error: 'invalid' | 'reused' };
    const outcome: Outcome = await t.db.tx(async (q): Promise<Outcome> => {
      const row = await SessionsRepo.lockRefreshToken(q, claims.jti);
      if (!row || row.token_hash !== sha256Hex(refreshToken) || row.session_id !== claims.sess || row.subject_id !== claims.sub) {
        return { error: 'invalid' };
      }
      if (row.session_revoked_at) return { error: 'invalid' };
      if (row.used_at || row.revoked_at) {
        await SessionsRepo.revokeSession(q, row.session_id, 'refresh_token_reuse');
        await writeAudit(q, {
          actorKind: 'system',
          action: 'session.refresh_reuse_detected',
          targetKind: row.subject_kind,
          targetId: row.subject_id,
          ip,
          details: { sessionId: row.session_id },
        });
        return { error: 'reused' };
      }
      if (row.expired) return { error: 'invalid' };

      const subject = await this.loadSubject(q, row.subject_kind, row.subject_id);
      if (!subject || subject.tokenVersion !== claims.tv || subject.role !== claims.role) {
        await SessionsRepo.revokeSession(q, row.session_id, 'account_changed');
        return { error: 'invalid' };
      }
      const jti = randomUUID();
      const base = { sid: t.salonId, sub: subject.id, role: subject.role, tv: subject.tokenVersion, sess: row.session_id };
      const next = this.tokens.signRefresh({ ...base, jti });
      await SessionsRepo.addRefreshToken(q, { id: jti, sessionId: row.session_id, tokenHash: sha256Hex(next.token), expiresAt: next.expiresAt });
      await SessionsRepo.markRotated(q, row.id, jti);
      return { ok: this.sessionResponse(t, subject, this.tokens.signAccess(base), next.token) };
    });
    if ('ok' in outcome) return outcome.ok;
    throw outcome.error === 'reused' ? Errors.refreshTokenReused() : Errors.invalidRefreshToken();
  }

  /** Revokes the session the refresh token belongs to. Idempotent; never reveals token validity. */
  async logout(refreshToken: string, ip: string): Promise<void> {
    const claims = this.tokens.verifyRefresh(refreshToken);
    if (!claims) return;
    const t = await this.resolver.fromVerifiedToken(claims.sid);
    if (!t) return;
    await t.db.tx(async (q) => {
      const row = await SessionsRepo.lockRefreshToken(q, claims.jti);
      if (!row || row.token_hash !== sha256Hex(refreshToken)) return;
      await SessionsRepo.revokeSession(q, row.session_id, 'logout');
      if (row.subject_kind === 'staff') {
        await writeAudit(q, { actorKind: 'staff', actorId: row.subject_id, action: 'staff.logout', targetKind: 'staff', targetId: row.subject_id, ip });
      }
    });
  }

  /** Current, non-suspended account state (used by refresh and by the request guard). */
  async loadSubject(q: TenantQueryable, kind: SubjectKind, id: string): Promise<Subject | null> {
    if (kind === 'staff') {
      const s = await StaffRepo.findById(q, id);
      if (!s || !s.active) return null;
      return { kind, id: s.id, role: s.role, tokenVersion: s.token_version, name: s.name };
    }
    const c = await CustomersRepo.findAccountById(q, id);
    if (!c || c.status === 'suspended') return null;
    return { kind, id: c.id, role: 'customer', tokenVersion: c.token_version, name: c.name, status: c.status };
  }

  /**
   * Validates an access token end-to-end: signature/expiry, salon (from the token only), account
   * still valid with the same token version, and session not revoked.
   */
  async authenticate(accessToken: string): Promise<{ tenant: TenantContext; principal: Principal } | null> {
    const claims = this.tokens.verifyAccess(accessToken);
    if (!claims) return null;
    const tenant = await this.resolver.fromVerifiedToken(claims.sid);
    if (!tenant || tenant.salon.status === 'suspended') return null;
    if (claims.role === 'customer' && tenant.salon.status !== 'active') return null;
    const kind: SubjectKind = claims.role === 'customer' ? 'customer' : 'staff';
    const [subject, alive] = await Promise.all([
      this.loadSubject(tenant.db, kind, claims.sub),
      SessionsRepo.isActive(tenant, claims.sess, kind, claims.sub),
    ]);
    if (!subject || !alive || subject.tokenVersion !== claims.tv || subject.role !== claims.role) return null;
    const principal: Principal = { salonId: tenant.salonId, subjectId: subject.id, role: subject.role, sessionId: claims.sess };
    if (kind === 'customer') principal.customerStatus = subject.status as 'pending' | 'active';
    return { tenant, principal };
  }
}

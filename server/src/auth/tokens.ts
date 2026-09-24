import { createHash, randomUUID } from 'node:crypto';
import * as jwt from 'jsonwebtoken';
import type { AppConfig } from '../config/config';
import type { Role } from './principal';

export interface AccessClaims {
  typ: 'access';
  sid: string; // salon id (directory)
  sub: string; // staff or customer id
  role: Role;
  tv: number; // token version of the account
  sess: string; // session (refresh-token family) id
}

export interface RefreshClaims {
  typ: 'refresh';
  sid: string;
  sub: string;
  role: Role;
  tv: number;
  sess: string;
  jti: string;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ROLES: Role[] = ['customer', 'barber', 'manager'];
const ACCESS_AUD = 'saloni-api';
const REFRESH_AUD = 'saloni-refresh';

export function sha256Hex(s: string): string {
  return createHash('sha256').update(s).digest('hex');
}

/** HS256 JWTs with separate secrets and audiences for access and refresh tokens. */
export class TokenService {
  constructor(private readonly cfg: AppConfig['auth']) {}

  signAccess(c: Omit<AccessClaims, 'typ'>): string {
    const { sub, ...rest } = c;
    return jwt.sign({ typ: 'access', ...rest }, this.cfg.accessSecret, {
      algorithm: 'HS256',
      expiresIn: this.cfg.accessTtlSec,
      issuer: this.cfg.issuer,
      audience: ACCESS_AUD,
      subject: sub,
      jwtid: randomUUID(),
    });
  }

  signRefresh(c: Omit<RefreshClaims, 'typ'>): { token: string; expiresAt: Date } {
    const { sub, jti, ...rest } = c;
    const ttlSec = this.cfg.refreshTtlDays * 86_400;
    const token = jwt.sign({ typ: 'refresh', ...rest }, this.cfg.refreshSecret, {
      algorithm: 'HS256',
      expiresIn: ttlSec,
      issuer: this.cfg.issuer,
      audience: REFRESH_AUD,
      subject: sub,
      jwtid: jti,
    });
    return { token, expiresAt: new Date(Date.now() + ttlSec * 1000) };
  }

  verifyAccess(token: string): AccessClaims | null {
    const p = this.verify(token, this.cfg.accessSecret, ACCESS_AUD);
    if (!p || p.typ !== 'access') return null;
    return { typ: 'access', sid: p.sid, sub: p.sub as string, role: p.role, tv: p.tv, sess: p.sess };
  }

  verifyRefresh(token: string): RefreshClaims | null {
    const p = this.verify(token, this.cfg.refreshSecret, REFRESH_AUD);
    if (!p || p.typ !== 'refresh' || typeof p.jti !== 'string' || !UUID_RE.test(p.jti)) return null;
    return { typ: 'refresh', sid: p.sid, sub: p.sub as string, role: p.role, tv: p.tv, sess: p.sess, jti: p.jti };
  }

  private verify(token: string, secret: string, audience: string): (jwt.JwtPayload & Record<string, any>) | null {
    if (typeof token !== 'string' || token.length > 4096) return null;
    try {
      const p = jwt.verify(token, secret, { algorithms: ['HS256'], issuer: this.cfg.issuer, audience });
      if (typeof p !== 'object' || p === null) return null;
      const ok =
        typeof p.sid === 'string' && UUID_RE.test(p.sid) &&
        typeof p.sub === 'string' && UUID_RE.test(p.sub) &&
        typeof p.sess === 'string' && UUID_RE.test(p.sess) &&
        ROLES.includes(p.role) &&
        Number.isInteger(p.tv);
      return ok ? (p as jwt.JwtPayload & Record<string, any>) : null;
    } catch {
      return null;
    }
  }
}

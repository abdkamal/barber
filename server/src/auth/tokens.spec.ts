import { randomUUID } from 'node:crypto';
import * as jwt from 'jsonwebtoken';
import { loadConfig } from '../config/config';
import { TokenService } from './tokens';

describe('TokenService', () => {
  const cfg = loadConfig({ NODE_ENV: 'test' } as NodeJS.ProcessEnv).auth;
  const t = new TokenService(cfg);
  const claims = { sid: randomUUID(), sub: randomUUID(), role: 'manager' as const, tv: 0, sess: randomUUID() };

  it('round-trips access tokens', () => {
    const tok = t.signAccess(claims);
    expect(t.verifyAccess(tok)).toEqual({ typ: 'access', ...claims });
    const decoded = jwt.decode(tok) as jwt.JwtPayload;
    expect(decoded.exp! - decoded.iat!).toBe(15 * 60);
  });

  it('does not accept a refresh token as an access token or vice versa', () => {
    const r = t.signRefresh({ ...claims, jti: randomUUID() }).token;
    expect(t.verifyAccess(r)).toBeNull();
    expect(t.verifyRefresh(t.signAccess(claims))).toBeNull();
    expect(t.verifyRefresh(r)?.sid).toBe(claims.sid);
  });

  it('rejects tampered, unsigned and foreign-secret tokens', () => {
    const tok = t.signAccess(claims);
    const [h, , s] = tok.split('.');
    const forgedPayload = Buffer.from(JSON.stringify({ ...jwt.decode(tok) as object, sid: randomUUID() })).toString('base64url');
    expect(t.verifyAccess(`${h}.${forgedPayload}.${s}`)).toBeNull();
    const none = jwt.sign({ typ: 'access', ...claims }, '', { algorithm: 'none' as jwt.Algorithm });
    expect(t.verifyAccess(none)).toBeNull();
    const foreign = jwt.sign({ typ: 'access', ...claims }, 'x'.repeat(40), { algorithm: 'HS256', issuer: cfg.issuer, audience: 'saloni-api' });
    expect(t.verifyAccess(foreign)).toBeNull();
  });

  it('rejects expired tokens', () => {
    const expired = new TokenService({ ...cfg, accessTtlSec: -10 }).signAccess(claims);
    expect(t.verifyAccess(expired)).toBeNull();
  });
});

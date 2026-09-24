import { loadConfig, parseTrustProxy } from './config';

import { randomBytes } from 'node:crypto';

/** A real-looking random secret (48 random bytes, base64url — what the README tells operators to generate). */
const S = (_tag: string) => randomBytes(48).toString('base64url');
const A = S('a');
const secrets = { JWT_ACCESS_SECRET: A, JWT_REFRESH_SECRET: S('b'), RESET_CODE_PEPPER: S('c') };
const env = (e: Record<string, string>) => e as NodeJS.ProcessEnv;

describe('configuration hardening (review M2/M3)', () => {
  it('M3: refuses to start unless NODE_ENV is set explicitly', () => {
    expect(() => loadConfig(env({ ...secrets }))).toThrow(/NODE_ENV must be set/);
    expect(() => loadConfig(env({ NODE_ENV: 'staging', ...secrets }))).toThrow(/NODE_ENV/);
  });

  it('M3: real secrets are required whenever NODE_ENV is not test — development included', () => {
    expect(() => loadConfig(env({ NODE_ENV: 'development' }))).toThrow(/JWT_ACCESS_SECRET must be set/);
    expect(() => loadConfig(env({ NODE_ENV: 'production' }))).toThrow(/must be set/);
    expect(() => loadConfig(env({ NODE_ENV: 'development', ...secrets, JWT_ACCESS_SECRET: 'dev-only-insecure-secret-change-me-0123456789' }))).toThrow(
      /placeholder/,
    );
    expect(() => loadConfig(env({ NODE_ENV: 'production', ...secrets, RESET_CODE_PEPPER: A }))).toThrow(/must all differ/);
    expect(loadConfig(env({ NODE_ENV: 'development', ...secrets })).auth.accessSecret).toBe(A);
    expect(loadConfig(env({ NODE_ENV: 'test' })).env).toBe('test'); // test keeps built-in secrets
  });

  it('M3 (round 2): the ">= 32 chars, distinct, no placeholder" rule is enforced whenever NODE_ENV is not test', () => {
    for (const NODE_ENV of ['development', 'production']) {
      // Too short once surrounding whitespace is ignored (padding must not satisfy the length).
      expect(() => loadConfig(env({ NODE_ENV, ...secrets, JWT_REFRESH_SECRET: `${' '.repeat(30)}abcdefghij0123` }))).toThrow(/JWT_REFRESH_SECRET must be at least 32/);
      expect(() => loadConfig(env({ NODE_ENV, ...secrets, RESET_CODE_PEPPER: 'k3Y-9qZ!'.repeat(3) }))).toThrow(/RESET_CODE_PEPPER must be at least 32/);
      // Long enough but not a real secret: repetitive, or a placeholder.
      expect(() => loadConfig(env({ NODE_ENV, ...secrets, JWT_ACCESS_SECRET: 'a'.repeat(64) }))).toThrow(/JWT_ACCESS_SECRET is too repetitive/);
      expect(() => loadConfig(env({ NODE_ENV, ...secrets, JWT_ACCESS_SECRET: 'abab'.repeat(16) }))).toThrow(/too repetitive/);
      expect(() => loadConfig(env({ NODE_ENV, ...secrets, JWT_ACCESS_SECRET: 'please-change-me-before-going-live-2026' }))).toThrow(/placeholder/);
      // An empty line in .env counts as "not set".
      expect(() => loadConfig(env({ NODE_ENV, ...secrets, JWT_ACCESS_SECRET: '   ' }))).toThrow(/JWT_ACCESS_SECRET must be set/);
      // The same secret twice (even with different padding) is refused.
      expect(() => loadConfig(env({ NODE_ENV, ...secrets, JWT_REFRESH_SECRET: ` ${A} ` }))).toThrow(/must all differ/);
    }
    // test keeps the built-in secrets and accepts short ones.
    expect(loadConfig(env({ NODE_ENV: 'test', JWT_ACCESS_SECRET: 'short' })).auth.accessSecret).toBe('short');
  });

  it('M2: TRUST_PROXY is false, a hop count or a proxy CIDR list; `true` is refused in production', () => {
    expect(parseTrustProxy('false', 'production')).toBe(false);
    expect(parseTrustProxy('1', 'production')).toBe(1);
    expect(parseTrustProxy('127.0.0.1, 10.0.0.0/8,::1/128', 'production')).toBe('127.0.0.1,10.0.0.0/8,::1/128');
    expect(parseTrustProxy('loopback', 'production')).toBe('loopback');
    expect(() => parseTrustProxy('true', 'production')).toThrow(/not allowed in production/);
    expect(parseTrustProxy('true', 'test')).toBe(true);
    expect(() => parseTrustProxy('10.0.0.0/33', 'production')).toThrow();
    expect(() => parseTrustProxy('everyone', 'development')).toThrow();
    expect(() => loadConfig(env({ NODE_ENV: 'production', ...secrets, TRUST_PROXY: 'true' }))).toThrow(/TRUST_PROXY/);
  });
});

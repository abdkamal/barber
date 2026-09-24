import { loadConfig, parseTrustProxy } from './config';

const S = (c: string) => c.repeat(40);
const secrets = { JWT_ACCESS_SECRET: S('a'), JWT_REFRESH_SECRET: S('b'), RESET_CODE_PEPPER: S('c') };
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
    expect(() => loadConfig(env({ NODE_ENV: 'production', ...secrets, RESET_CODE_PEPPER: S('a') }))).toThrow(/must all differ/);
    expect(loadConfig(env({ NODE_ENV: 'development', ...secrets })).auth.accessSecret).toBe(S('a'));
    expect(loadConfig(env({ NODE_ENV: 'test' })).env).toBe('test'); // test keeps built-in secrets
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

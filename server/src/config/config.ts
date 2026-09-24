import { isIP } from 'node:net';
import { z } from 'zod';

/**
 * All runtime configuration comes from environment variables (see .env.example).
 * Review M3: NODE_ENV must be set explicitly, and real secrets are required whenever it is not
 * `test` — a forgotten variable never silently runs a server with well-known dev secrets.
 */
const bool = z
  .union([z.boolean(), z.string()])
  .transform((v) => (typeof v === 'boolean' ? v : ['1', 'true', 'yes', 'on'].includes(v.toLowerCase())));
const int = (def: number) => z.coerce.number().int().default(def);

const TEST_SECRET = 'test-only-insecure-secret-0123456789abcdef';
/** Placeholders that must never be accepted as real secrets. */
const WEAK_SECRET_RE = /change[-_ ]?me|dev[-_]only|insecure|example|placeholder|secret-?here|^(x+|0+|1+|test|secret|password)$/i;
export const MIN_SECRET_LENGTH = 32;
/** A real (random) secret of >= 32 chars has far more distinct characters than this. */
const MIN_DISTINCT_SECRET_CHARS = 10;

/**
 * Review M3 / round 2 (item 5): whenever NODE_ENV is not `test`, each secret must be present,
 * at least 32 characters (surrounding whitespace does not count), not a placeholder and not a
 * trivially repetitive string. Returns the problem, or null when the secret is acceptable.
 */
export function secretProblem(v: string): string | null {
  const s = v.trim();
  if (s.length < MIN_SECRET_LENGTH) return `must be at least ${MIN_SECRET_LENGTH} characters`;
  if (WEAK_SECRET_RE.test(s)) return 'looks like a placeholder — generate a real secret';
  if (new Set(s).size < MIN_DISTINCT_SECRET_CHARS) return 'is too repetitive to be a real secret — generate a random one';
  return null;
}

const EnvSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production'], { message: 'NODE_ENV must be set explicitly to development, test or production' }),
  HOST: z.string().default('0.0.0.0'),
  PORT: int(3000),

  // Runtime connections (normally through PgBouncer, transaction pooling).
  PG_HOST: z.string().default('127.0.0.1'),
  PG_PORT: int(6432),
  PG_USER: z.string().default('saloni'),
  PG_PASSWORD: z.string().default('saloni_dev_password'),
  // Administrative connections (CREATE DATABASE, migrations) go DIRECTLY to PostgreSQL.
  PG_ADMIN_HOST: z.string().default('127.0.0.1'),
  PG_ADMIN_PORT: int(5432),
  PG_ADMIN_USER: z.string().default('saloni'),
  PG_ADMIN_PASSWORD: z.string().default('saloni_dev_password'),
  PG_ADMIN_MAINTENANCE_DB: z.string().default('postgres'),

  DIRECTORY_DB_NAME: z.string().regex(/^[a-z][a-z0-9_]{0,62}$/).default('saloni_directory'),
  SALON_DB_PREFIX: z.string().regex(/^[a-z][a-z0-9_]{0,40}$/).default('saloni_salon_'),
  DIRECTORY_POOL_MAX: int(5),
  TENANT_POOL_MAX: int(3),
  TENANT_POOL_IDLE_TTL_MS: int(5 * 60_000),
  TENANT_POOLS_MAX: int(200),
  DIRECTORY_CACHE_TTL_MS: int(5_000),

  // Secrets are validated in loadConfig (secretFrom): >= 32 chars, not a placeholder, all different.
  JWT_ACCESS_SECRET: z.string().optional(),
  JWT_REFRESH_SECRET: z.string().optional(),
  JWT_ISSUER: z.string().default('saloni'),
  ACCESS_TOKEN_TTL_SEC: int(15 * 60),
  REFRESH_TOKEN_TTL_DAYS: int(30),
  RESET_CODE_PEPPER: z.string().optional(),
  // Round 2 (item 7): a rotated refresh token may be presented once more within this window.
  REFRESH_REUSE_GRACE_SEC: int(30),
  RESET_CODE_TTL_HOURS: int(24),

  ARGON2_MEMORY_KIB: int(19_456),
  ARGON2_TIME_COST: int(2),
  ARGON2_PARALLELISM: int(1),

  TRUST_PROXY: z.string().default('false'),
  CORS_ORIGINS: z.string().default(''),

  BACKOFF_FREE_ATTEMPTS: int(3),
  BACKOFF_BASE_MS: int(1_000),
  BACKOFF_MAX_MS: int(15 * 60_000),
  BACKOFF_IP_FREE_ATTEMPTS: int(20),
  BACKOFF_RESET_AFTER_MS: int(60 * 60_000),
  // Account-wide (all IPs) slow delay — never a lockout (review M1).
  BACKOFF_ACCOUNT_FREE_ATTEMPTS: int(10),
  BACKOFF_ACCOUNT_BASE_MS: int(250),
  BACKOFF_ACCOUNT_MAX_DELAY_MS: int(3_000),

  RATE_LIMITS_ENABLED: bool.default(true),
  // Review M4: at most this many salons may wait for activation at once (self-registration pauses beyond).
  MAX_PENDING_SALONS: int(50),
});

export interface RateLimitRule {
  limit: number;
  windowMs: number;
}

export interface AccountRules {
  ip: RateLimitRule;
  accountIp: RateLimitRule;
  account: RateLimitRule;
}

export interface AppConfig {
  env: 'development' | 'test' | 'production';
  host: string;
  port: number;
  db: {
    runtime: { host: string; port: number; user: string; password: string };
    admin: { host: string; port: number; user: string; password: string; maintenanceDb: string };
    directoryDbName: string;
    salonDbPrefix: string;
    directoryPoolMax: number;
    tenantPoolMax: number;
    tenantPoolIdleTtlMs: number;
    tenantPoolsMax: number;
    directoryCacheTtlMs: number;
  };
  auth: {
    accessSecret: string;
    refreshSecret: string;
    issuer: string;
    accessTtlSec: number;
    refreshTtlDays: number;
    resetCodePepper: string;
    resetCodeTtlHours: number;
    /** Round 2 (item 7): grace for re-presenting the directly preceding refresh token (0 = off). */
    refreshReuseGraceSec: number;
    argon2: { memoryCost: number; timeCost: number; parallelism: number };
  };
  backoff: {
    freeAttempts: number;
    baseMs: number;
    maxMs: number;
    ipFreeAttempts: number;
    resetAfterMs: number;
    accountFreeAttempts: number;
    accountBaseMs: number;
    accountMaxDelayMs: number;
  };
  http: { trustProxy: boolean | number | string; corsOrigins: string[] };
  provisioning: { maxPendingSalons: number };
  rateLimits: {
    enabled: boolean;
    /** Default per-IP limit applied to every route without a specific rule. */
    global: RateLimitRule;
    /**
     * Round 2 (item 6, review M1): `ip` and `accountIp` (one account from one address) are hard
     * limits (429). `account` (one account from ALL addresses) is DELAY-ONLY: beyond its limit each
     * request is slowed down progressively (capped at `backoff.accountMaxDelayMs`), never refused —
     * so nobody can lock a real user out of his own account from other addresses.
     */
    login: AccountRules;
    register: AccountRules;
    salonRegister: { ip: RateLimitRule };
    refresh: { ip: RateLimitRule };
    passwordReset: AccountRules;
    publicLookup: { ip: RateLimitRule };
    sensitive: { ip: RateLimitRule };
    /** Device sync pushes per staff account (review M4). */
    sync: { account: RateLimitRule };
  };
}

const PROXY_NAMES = new Set(['loopback', 'linklocal', 'uniquelocal']);

function isCidrOrIp(v: string): boolean {
  const [addr, bits, ...rest] = v.split('/');
  if (rest.length || !addr) return false;
  const family = isIP(addr);
  if (!family) return false;
  if (bits === undefined) return true;
  if (!/^\d{1,3}$/.test(bits)) return false;
  return Number(bits) <= (family === 4 ? 32 : 128);
}

/**
 * Review M2: which proxies' X-Forwarded-For is trusted for the client IP (rate limits, backoff).
 * Allowed: `false`/empty, a hop count (e.g. `1` behind one nginx), or a comma-separated list of
 * proxy addresses/CIDRs (Express names loopback/linklocal/uniquelocal too). `true` (trust every
 * hop — any client could spoof its IP) is refused in production.
 */
export function parseTrustProxy(v: string, env: AppConfig['env']): boolean | number | string {
  const s = v.trim();
  if (s === 'false' || s === '') return false;
  if (s === 'true') {
    if (env === 'production') throw new Error('TRUST_PROXY=true is not allowed in production: set the hop count (e.g. 1) or the proxy CIDR list');
    return true;
  }
  if (/^\d+$/.test(s)) {
    const n = Number(s);
    if (n < 0 || n > 10) throw new Error('TRUST_PROXY hop count must be between 0 and 10');
    return n;
  }
  const parts = s.split(',').map((p) => p.trim()).filter(Boolean);
  if (!parts.length || !parts.every((p) => PROXY_NAMES.has(p) || isCidrOrIp(p))) {
    throw new Error('TRUST_PROXY must be false, a hop count, or a comma-separated list of proxy IPs/CIDRs');
  }
  return parts.join(',');
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  if (!env.NODE_ENV) throw new Error('NODE_ENV must be set explicitly (development, test or production)');
  const parsed = EnvSchema.safeParse(env);
  if (!parsed.success) throw new Error(`invalid configuration: ${parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; ')}`);
  const e = parsed.data;
  const isTest = e.NODE_ENV === 'test';
  const secret = (v: string | undefined, name: string): string => {
    const given = v?.trim() ? v.trim() : undefined; // an empty `NAME=` line in .env is "not set"
    if (given) {
      if (!isTest) {
        const problem = secretProblem(given);
        if (problem) throw new Error(`${name} ${problem} (>= ${MIN_SECRET_LENGTH} chars, all different, no placeholders)`);
      }
      return given;
    }
    if (!isTest) throw new Error(`${name} must be set (>= ${MIN_SECRET_LENGTH} chars) unless NODE_ENV=test`);
    return `${TEST_SECRET}-${name}`;
  };
  const accessSecret = secret(e.JWT_ACCESS_SECRET, 'JWT_ACCESS_SECRET');
  const refreshSecret = secret(e.JWT_REFRESH_SECRET, 'JWT_REFRESH_SECRET');
  const pepper = secret(e.RESET_CODE_PEPPER, 'RESET_CODE_PEPPER');
  if (new Set([accessSecret, refreshSecret, pepper]).size !== 3) {
    throw new Error('JWT_ACCESS_SECRET, JWT_REFRESH_SECRET and RESET_CODE_PEPPER must all differ');
  }
  const min = 60_000;
  const hour = 60 * min;
  return {
    env: e.NODE_ENV,
    host: e.HOST,
    port: e.PORT,
    db: {
      runtime: { host: e.PG_HOST, port: e.PG_PORT, user: e.PG_USER, password: e.PG_PASSWORD },
      admin: {
        host: e.PG_ADMIN_HOST,
        port: e.PG_ADMIN_PORT,
        user: e.PG_ADMIN_USER,
        password: e.PG_ADMIN_PASSWORD,
        maintenanceDb: e.PG_ADMIN_MAINTENANCE_DB,
      },
      directoryDbName: e.DIRECTORY_DB_NAME,
      salonDbPrefix: e.SALON_DB_PREFIX,
      directoryPoolMax: e.DIRECTORY_POOL_MAX,
      tenantPoolMax: e.TENANT_POOL_MAX,
      tenantPoolIdleTtlMs: e.TENANT_POOL_IDLE_TTL_MS,
      tenantPoolsMax: e.TENANT_POOLS_MAX,
      directoryCacheTtlMs: e.DIRECTORY_CACHE_TTL_MS,
    },
    auth: {
      accessSecret,
      refreshSecret,
      issuer: e.JWT_ISSUER,
      accessTtlSec: e.ACCESS_TOKEN_TTL_SEC,
      refreshTtlDays: e.REFRESH_TOKEN_TTL_DAYS,
      resetCodePepper: pepper,
      resetCodeTtlHours: e.RESET_CODE_TTL_HOURS,
      refreshReuseGraceSec: Math.max(0, Math.min(e.REFRESH_REUSE_GRACE_SEC, 120)),
      argon2: { memoryCost: e.ARGON2_MEMORY_KIB, timeCost: e.ARGON2_TIME_COST, parallelism: e.ARGON2_PARALLELISM },
    },
    backoff: {
      freeAttempts: e.BACKOFF_FREE_ATTEMPTS,
      baseMs: e.BACKOFF_BASE_MS,
      maxMs: e.BACKOFF_MAX_MS,
      ipFreeAttempts: e.BACKOFF_IP_FREE_ATTEMPTS,
      resetAfterMs: e.BACKOFF_RESET_AFTER_MS,
      accountFreeAttempts: e.BACKOFF_ACCOUNT_FREE_ATTEMPTS,
      accountBaseMs: e.BACKOFF_ACCOUNT_BASE_MS,
      accountMaxDelayMs: Math.min(e.BACKOFF_ACCOUNT_MAX_DELAY_MS, 10_000),
    },
    http: {
      trustProxy: parseTrustProxy(e.TRUST_PROXY, e.NODE_ENV),
      corsOrigins: e.CORS_ORIGINS.split(',').map((s) => s.trim()).filter(Boolean),
    },
    provisioning: { maxPendingSalons: e.MAX_PENDING_SALONS },
    rateLimits: {
      enabled: e.RATE_LIMITS_ENABLED,
      global: { limit: 300, windowMs: min },
      login: { ip: { limit: 30, windowMs: 15 * min }, accountIp: { limit: 10, windowMs: 15 * min }, account: { limit: 10, windowMs: 15 * min } },
      register: { ip: { limit: 10, windowMs: hour }, accountIp: { limit: 5, windowMs: hour }, account: { limit: 5, windowMs: hour } },
      salonRegister: { ip: { limit: 3, windowMs: hour } },
      refresh: { ip: { limit: 60, windowMs: 15 * min } },
      passwordReset: { ip: { limit: 10, windowMs: 15 * min }, accountIp: { limit: 5, windowMs: 15 * min }, account: { limit: 5, windowMs: 15 * min } },
      publicLookup: { ip: { limit: 60, windowMs: min } },
      sensitive: { ip: { limit: 60, windowMs: 15 * min } },
      sync: { account: { limit: 60, windowMs: min } },
    },
  };
}

export const APP_CONFIG = Symbol('APP_CONFIG');

/** Loads ./.env into process.env when present (real environment variables take precedence). */
export function loadDotEnv(path = '.env'): void {
  try {
    const before = { ...process.env };
    process.loadEnvFile(path);
    Object.assign(process.env, before);
  } catch {
    /* no .env file — rely on the environment */
  }
}

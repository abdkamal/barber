import { z } from 'zod';

/**
 * All runtime configuration comes from environment variables (see .env.example).
 * Secrets have no defaults outside development/test.
 */
const bool = z
  .union([z.boolean(), z.string()])
  .transform((v) => (typeof v === 'boolean' ? v : ['1', 'true', 'yes', 'on'].includes(v.toLowerCase())));
const int = (def: number) => z.coerce.number().int().default(def);

const DEV_SECRET = 'dev-only-insecure-secret-change-me-0123456789';

const EnvSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
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

  JWT_ACCESS_SECRET: z.string().min(32).optional(),
  JWT_REFRESH_SECRET: z.string().min(32).optional(),
  JWT_ISSUER: z.string().default('saloni'),
  ACCESS_TOKEN_TTL_SEC: int(15 * 60),
  REFRESH_TOKEN_TTL_DAYS: int(30),
  RESET_CODE_PEPPER: z.string().min(32).optional(),
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

  RATE_LIMITS_ENABLED: bool.default(true),
});

export interface RateLimitRule {
  limit: number;
  windowMs: number;
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
    argon2: { memoryCost: number; timeCost: number; parallelism: number };
  };
  backoff: {
    freeAttempts: number;
    baseMs: number;
    maxMs: number;
    ipFreeAttempts: number;
    resetAfterMs: number;
  };
  http: { trustProxy: boolean | number | string; corsOrigins: string[] };
  rateLimits: {
    enabled: boolean;
    /** Default per-IP limit applied to every route without a specific rule. */
    global: RateLimitRule;
    login: { ip: RateLimitRule; account: RateLimitRule };
    register: { ip: RateLimitRule; account: RateLimitRule };
    salonRegister: { ip: RateLimitRule };
    refresh: { ip: RateLimitRule };
    passwordReset: { ip: RateLimitRule; account: RateLimitRule };
    publicLookup: { ip: RateLimitRule };
    sensitive: { ip: RateLimitRule };
  };
}

function parseTrustProxy(v: string): boolean | number | string {
  if (v === 'false' || v === '') return false;
  if (v === 'true') return true;
  if (/^\d+$/.test(v)) return Number(v);
  return v; // e.g. "loopback" or a subnet list understood by Express
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const e = EnvSchema.parse(env);
  const isProd = e.NODE_ENV === 'production';
  const secret = (v: string | undefined, name: string): string => {
    if (v) return v;
    if (isProd) throw new Error(`${name} must be set in production`);
    return `${DEV_SECRET}-${name}`;
  };
  const accessSecret = secret(e.JWT_ACCESS_SECRET, 'JWT_ACCESS_SECRET');
  const refreshSecret = secret(e.JWT_REFRESH_SECRET, 'JWT_REFRESH_SECRET');
  if (accessSecret === refreshSecret) throw new Error('JWT_ACCESS_SECRET and JWT_REFRESH_SECRET must differ');
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
      resetCodePepper: secret(e.RESET_CODE_PEPPER, 'RESET_CODE_PEPPER'),
      resetCodeTtlHours: e.RESET_CODE_TTL_HOURS,
      argon2: { memoryCost: e.ARGON2_MEMORY_KIB, timeCost: e.ARGON2_TIME_COST, parallelism: e.ARGON2_PARALLELISM },
    },
    backoff: {
      freeAttempts: e.BACKOFF_FREE_ATTEMPTS,
      baseMs: e.BACKOFF_BASE_MS,
      maxMs: e.BACKOFF_MAX_MS,
      ipFreeAttempts: e.BACKOFF_IP_FREE_ATTEMPTS,
      resetAfterMs: e.BACKOFF_RESET_AFTER_MS,
    },
    http: {
      trustProxy: parseTrustProxy(e.TRUST_PROXY),
      corsOrigins: e.CORS_ORIGINS.split(',').map((s) => s.trim()).filter(Boolean),
    },
    rateLimits: {
      enabled: e.RATE_LIMITS_ENABLED,
      global: { limit: 300, windowMs: min },
      login: { ip: { limit: 30, windowMs: 15 * min }, account: { limit: 10, windowMs: 15 * min } },
      register: { ip: { limit: 10, windowMs: hour }, account: { limit: 5, windowMs: hour } },
      salonRegister: { ip: { limit: 3, windowMs: hour } },
      refresh: { ip: { limit: 60, windowMs: 15 * min } },
      passwordReset: { ip: { limit: 10, windowMs: 15 * min }, account: { limit: 5, windowMs: 15 * min } },
      publicLookup: { ip: { limit: 60, windowMs: min } },
      sensitive: { ip: { limit: 60, windowMs: 15 * min } },
    },
  };
}

export const APP_CONFIG = Symbol('APP_CONFIG');

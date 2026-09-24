import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import type TestAgent from 'supertest/lib/agent';
import { createApp } from '../src/bootstrap';
import { AppConfig, loadConfig } from '../src/config/config';
import { PoolManager } from '../src/db/pools';
import { VendorService } from '../src/provisioning/vendor.service';

export const TEST_DIRECTORY = 'saloni_test_directory';
export const TEST_PREFIX = 'saloni_test_s_';

/** Test configuration: dedicated test databases, cheaper Argon2, no directory cache, proxies trusted. */
export function testConfig(env: Record<string, string> = {}): AppConfig {
  const pass = (k: string) => (process.env[k] ? { [k]: process.env[k]! } : {});
  return loadConfig({
    NODE_ENV: 'test',
    ...pass('PG_HOST'), ...pass('PG_PORT'), ...pass('PG_USER'), ...pass('PG_PASSWORD'),
    ...pass('PG_ADMIN_HOST'), ...pass('PG_ADMIN_PORT'), ...pass('PG_ADMIN_USER'), ...pass('PG_ADMIN_PASSWORD'),
    DIRECTORY_DB_NAME: TEST_DIRECTORY,
    SALON_DB_PREFIX: TEST_PREFIX,
    ARGON2_MEMORY_KIB: '4096',
    DIRECTORY_CACHE_TTL_MS: '0',
    RATE_LIMITS_ENABLED: 'false',
    TRUST_PROXY: 'true',
    ...env,
  } as NodeJS.ProcessEnv);
}

export interface TestContext {
  app: INestApplication;
  config: AppConfig;
  http: () => TestAgent;
  pools: PoolManager;
  vendor: VendorService;
  close: () => Promise<void>;
}

export async function startApp(config = testConfig()): Promise<TestContext> {
  const app = await createApp(config, { logger: false });
  await app.init();
  const pools = new PoolManager(config);
  return {
    app,
    config,
    http: () => request(app.getHttpServer()),
    pools,
    vendor: new VendorService(config, pools),
    close: async () => {
      await app.close();
      await pools.close();
    },
  };
}

let seq = 0;
export function uniq(prefix: string): string {
  seq++;
  return `${prefix}${Date.now().toString(36).slice(-4)}${seq}`;
}

export const STAFF_PW = 'staff-password-1';
export const CUSTOMER_PW = 'cust-pass1';

export interface SalonFixture {
  id: string;
  code: string;
  dbName: string;
  manager: { username: string; accessToken: string; refreshToken: string; id: string };
}

/** Registers a salon through the public API; activates it through the vendor CLI service unless told not to. */
export async function createSalon(ctx: TestContext, name: string, opts: { activate?: boolean } = {}): Promise<SalonFixture> {
  const username = uniq('owner').toLowerCase();
  const res = await ctx
    .http()
    .post('/v1/salons/register')
    .send({ salon: { name, timezone: 'Asia/Riyadh', currency: 'SAR' }, owner: { name: 'Owner', username, password: STAFF_PW } });
  if (res.status !== 201) throw new Error(`register failed: ${res.status} ${JSON.stringify(res.body)}`);
  const code: string = res.body.salon.code;
  if (opts.activate !== false) await ctx.vendor.activate(code);
  const rec = (await ctx.vendor.list()).find((s) => s.code === code)!;
  return {
    id: rec.id,
    code,
    dbName: rec.db_name,
    manager: {
      username,
      accessToken: res.body.session.accessToken,
      refreshToken: res.body.session.refreshToken,
      id: res.body.session.account.id,
    },
  };
}

export async function createBarber(ctx: TestContext, salon: SalonFixture, username = uniq('barber').toLowerCase()) {
  const res = await ctx
    .http()
    .post('/v1/manager/staff')
    .set('Authorization', `Bearer ${salon.manager.accessToken}`)
    .send({ name: 'Barber', username, password: STAFF_PW, role: 'barber' });
  if (res.status !== 201) throw new Error(`create barber failed: ${res.status} ${JSON.stringify(res.body)}`);
  return { id: res.body.id as string, username };
}

export async function staffLogin(ctx: TestContext, code: string, username: string, password = STAFF_PW, ip?: string) {
  const r = ctx.http().post('/v1/auth/staff/login');
  if (ip) r.set('X-Forwarded-For', ip);
  return r.send({ salonCode: code, username, password });
}

export async function registerCustomer(ctx: TestContext, code: string, phone: string, password = CUSTOMER_PW) {
  return ctx.http().post('/v1/auth/customer/register').send({ salonCode: code, name: 'زبون', phone, password });
}

export function randomPhone(): string {
  return '05' + String(Math.floor(Math.random() * 1e8)).padStart(8, '0');
}

/** Direct admin query on a salon database (bypasses the app — for assertions only). */
export async function salonQuery<T = any>(ctx: TestContext, dbName: string, sql: string, params: unknown[] = []): Promise<T[]> {
  const c = await ctx.pools.adminClient(dbName);
  try {
    return (await c.query(sql, params)).rows as T[];
  } finally {
    await c.end();
  }
}

export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

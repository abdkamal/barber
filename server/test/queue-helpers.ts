import { randomUUID } from 'node:crypto';
import { NotificationService } from '../src/notifications/notification.service';
import { FakeNotifier, NOTIFIER } from '../src/notifications/notifier';
import { SchedulerService } from '../src/scheduler/scheduler.service';
import { Clock } from '../src/scheduling/clock';
import { TenantResolver } from '../src/tenancy/tenant-resolver.service';
import {
  createBarber,
  createSalon,
  randomPhone,
  registerCustomer,
  SalonFixture,
  salonQuery,
  staffLogin,
  TestContext,
} from './helpers';

export const MIN = 60_000;
/** Thursday 2026-03-05, 10:00 in Asia/Riyadh (UTC+3, no DST). */
export const T0 = Date.parse('2026-03-05T07:00:00Z');
export const at = (minutesFromT0: number) => T0 + minutesFromT0 * MIN;
export const isoAt = (minutesFromT0: number) => new Date(at(minutesFromT0)).toISOString();

export interface Barber {
  id: string;
  username: string;
  token: string;
  seq: number;
}

export interface Customer {
  id: string;
  token: string;
  phone: string;
}

export interface QueueSalon extends SalonFixture {
  services: { haircut: string; beard: string; long: string };
  barbers: Barber[];
}

export const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

export function clock(ctx: TestContext): Clock {
  return ctx.app.get(Clock);
}

export function fake(ctx: TestContext): FakeNotifier {
  return ctx.app.get<FakeNotifier>(NOTIFIER);
}

/**
 * A salon with three services and `barbers` barbers working 09:00–23:00 (Riyadh) every day.
 * Services: haircut 30 min / 50.00, beard 15 min / 25.00, long 60 min / 100.00.
 */
const created = new Map<TestContext, SalonFixture[]>();

export async function setupQueueSalon(ctx: TestContext, opts: { barbers?: number; opens?: string; closes?: string } = {}): Promise<QueueSalon> {
  const salon = await createSalon(ctx, 'صالون الطابور');
  created.set(ctx, [...(created.get(ctx) ?? []), salon]);
  const [haircut] = await salonQuery(ctx, salon.dbName, "INSERT INTO services (name, base_duration_minutes, price_minor, position) VALUES ('قص', 30, 5000, 1) RETURNING id");
  const [beard] = await salonQuery(ctx, salon.dbName, "INSERT INTO services (name, base_duration_minutes, price_minor, position) VALUES ('لحية', 15, 2500, 2) RETURNING id");
  const [long] = await salonQuery(ctx, salon.dbName, "INSERT INTO services (name, base_duration_minutes, price_minor, position) VALUES ('باقة', 60, 10000, 3) RETURNING id");
  const barbers: Barber[] = [];
  for (let i = 0; i < (opts.barbers ?? 1); i++) {
    const b = await createBarber(ctx, salon);
    for (let d = 0; d < 7; d++) {
      await salonQuery(ctx, salon.dbName, 'INSERT INTO work_schedules (staff_id, weekday, opens_at, closes_at) VALUES ($1, $2, $3, $4)', [
        b.id,
        d,
        opts.opens ?? '09:00',
        opts.closes ?? '23:00',
      ]);
    }
    const login = await staffLogin(ctx, salon.code, b.username);
    if (login.status !== 200) throw new Error(`barber login failed ${login.status}`);
    barbers.push({ ...b, token: login.body.accessToken, seq: 0 });
  }
  return { ...salon, services: { haircut: haircut.id, beard: beard.id, long: long.id }, barbers };
}

export async function newCustomer(ctx: TestContext, salon: SalonFixture): Promise<Customer> {
  const phone = randomPhone();
  const r = await registerCustomer(ctx, salon.code, phone);
  if (r.status !== 201) throw new Error(`customer register failed ${r.status} ${JSON.stringify(r.body)}`);
  return { id: r.body.account.id, token: r.body.accessToken, phone };
}

export async function book(ctx: TestContext, c: Customer, body: Record<string, unknown>, key: string = randomUUID()) {
  return ctx.http().post('/v1/bookings').set(auth(c.token)).set('Idempotency-Key', key).send(body);
}

export async function heartbeat(ctx: TestContext, b: Barber) {
  const r = await ctx.http().post('/v1/heartbeat').set(auth(b.token)).send({ deviceSeq: ++b.seq, queueDigest: 'x' });
  if (r.status !== 200) throw new Error(`heartbeat failed ${r.status} ${JSON.stringify(r.body)}`);
  return r.body;
}

export function event(ctx: TestContext, b: Barber, type: string, bookingId: string | null, payload: Record<string, unknown> = {}, occurredAt?: number, extra: Record<string, unknown> = {}) {
  return {
    id: randomUUID(),
    deviceSeq: ++b.seq,
    type,
    bookingId,
    occurredAt: new Date(occurredAt ?? clock(ctx).now()).toISOString(),
    approximate: false,
    payload,
    ...extra,
  };
}

export async function push(ctx: TestContext, b: Barber, events: unknown[]) {
  const r = await ctx.http().post('/v1/sync/events').set(auth(b.token)).send({ events });
  if (r.status !== 200) throw new Error(`sync failed ${r.status} ${JSON.stringify(r.body)}`);
  return r.body as Array<{ eventId: string; result: string; reason?: string }>;
}

export async function staffToday(ctx: TestContext, b: Barber) {
  const r = await ctx.http().get('/v1/staff/today').set(auth(b.token));
  if (r.status !== 200) throw new Error(`today failed ${r.status} ${JSON.stringify(r.body)}`);
  return r.body;
}

/** Runs the scheduler for one salon now and waits for notification dispatch. */
export async function runScheduler(ctx: TestContext, salon: SalonFixture) {
  const t = await ctx.app.get(TenantResolver).fromVerifiedToken(salon.id);
  await ctx.app.get(SchedulerService).runSalon(t!);
  await ctx.app.get(NotificationService).idle();
}

export async function settle(ctx: TestContext) {
  await ctx.app.get(NotificationService).idle();
}

export async function notifications(ctx: TestContext, salon: SalonFixture, where = 'TRUE', params: unknown[] = []) {
  return salonQuery(ctx, salon.dbName, `SELECT * FROM notifications WHERE ${where} ORDER BY created_at, id`, params);
}

export async function registerDevice(ctx: TestContext, token: string, fcmToken: string) {
  const r = await ctx.http().post('/v1/devices').set(auth(token)).send({ fcmToken, notificationsAllowed: true, hasPlayServices: true });
  if (r.status !== 200) throw new Error(`device failed ${r.status} ${JSON.stringify(r.body)}`);
}

/** Moves the clock minute by minute with a heartbeat each minute (the barber stays connected). */
export async function liveUntil(ctx: TestContext, b: Barber, minutesFromT0: number) {
  const c = clock(ctx);
  while (c.now() < at(minutesFromT0)) {
    c.set(Math.min(c.now() + MIN, at(minutesFromT0)));
    await heartbeat(ctx, b);
  }
}

/**
 * Drops the salons a suite created (database + directory row). PgBouncer keeps idle server
 * connections per database for minutes; without this, many suites exhaust max_connections.
 */
export async function closeQueueApp(ctx: TestContext) {
  await ctx.close();
  await dropCreatedSalons(ctx);
}

export async function dropCreatedSalons(ctx: TestContext) {
  const salons = created.get(ctx) ?? [];
  created.delete(ctx);
  if (!salons.length) return;
  const { PoolManager } = await import('../src/db/pools');
  const pools = new PoolManager(ctx.config);
  try {
    const admin = await pools.adminClient();
    try {
      for (const s of salons) await admin.query(`DROP DATABASE IF EXISTS "${s.dbName}" WITH (FORCE)`);
    } finally {
      await admin.end();
    }
    const dir = await pools.adminClient(ctx.config.db.directoryDbName);
    try {
      await dir.query('DELETE FROM salons WHERE id = ANY($1::uuid[])', [salons.map((s) => s.id)]);
    } finally {
      await dir.end();
    }
  } finally {
    await pools.close();
  }
}

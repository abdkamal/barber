import { randomUUID } from 'node:crypto';
import type { Client } from 'pg';
import { PoolManager } from '../src/db/pools';
import { createSalon, SalonFixture, sleep, startApp, testConfig, TestContext } from './helpers';

describe('salon schema guarantees', () => {
  let ctx: TestContext;
  let S: SalonFixture;
  let db: Client;

  beforeAll(async () => {
    ctx = await startApp();
    S = await createSalon(ctx, 'Schema Salon');
    db = await ctx.pools.adminClient(S.dbName);
  });
  afterAll(async () => {
    await db.end();
    await ctx.close();
  });

  async function seedBooking(): Promise<string> {
    const [{ id: staffId }] = (await db.query('SELECT id FROM staff LIMIT 1')).rows;
    const { rows: [c] } = await db.query("INSERT INTO customers (name, phone) VALUES ('حاضر', '0500000000') RETURNING id");
    const { rows: [b] } = await db.query(
      `INSERT INTO bookings (customer_id, staff_id, kind, status, source, work_date)
       VALUES ($1, $2, 'queue', 'waiting', 'barber', current_date) RETURNING id`,
      [c.id, staffId],
    );
    return b.id;
  }

  it('booking_events is append-only (UPDATE / DELETE / TRUNCATE rejected, even for the owner role)', async () => {
    const bookingId = await seedBooking();
    const { rows: [ev] } = await db.query(
      `INSERT INTO booking_events (booking_id, type, payload, occurred_at, actor_kind, reason)
       VALUES ($1, 'created', '{"x":1}', now(), 'system', 'test') RETURNING id`,
      [bookingId],
    );
    await expect(db.query("UPDATE booking_events SET reason = 'tampered' WHERE id = $1", [ev.id])).rejects.toThrow(/append-only/);
    await expect(db.query('DELETE FROM booking_events WHERE id = $1', [ev.id])).rejects.toThrow(/append-only/);
    await expect(db.query('TRUNCATE booking_events CASCADE')).rejects.toThrow(/append-only/);
    const { rows } = await db.query('SELECT reason FROM booking_events WHERE id = $1', [ev.id]);
    expect(rows[0].reason).toBe('test');
  });

  it('device events are deduplicated by (device, seq)', async () => {
    const device = randomUUID();
    const ins = () =>
      db.query(
        `INSERT INTO booking_events (type, occurred_at, actor_kind, device_id, device_seq) VALUES ('heartbeat', now(), 'staff', $1, 7)`,
        [device],
      );
    await ins();
    await expect(ins()).rejects.toThrow(/duplicate key/);
  });

  it('audit_log is append-only too', async () => {
    await expect(db.query("UPDATE audit_log SET action = 'x'")).rejects.toThrow(/append-only/);
    await expect(db.query('DELETE FROM audit_log')).rejects.toThrow(/append-only/);
  });

  it('booking_services keeps a price snapshot and money is integer minor units', async () => {
    const bookingId = await seedBooking();
    const { rows: [svc] } = await db.query(
      "INSERT INTO services (name, base_duration_minutes, price_minor) VALUES ('قص', 30, 3500) RETURNING id",
    );
    await db.query(
      `INSERT INTO booking_services (booking_id, service_id, name_snapshot, price_minor, duration_minutes_snapshot)
       VALUES ($1, $2, 'قص', 3500, 30)`,
      [bookingId, svc.id],
    );
    await db.query('UPDATE services SET price_minor = 5000 WHERE id = $1', [svc.id]);
    const { rows } = await db.query('SELECT price_minor FROM booking_services WHERE booking_id = $1', [bookingId]);
    expect(Number(rows[0].price_minor)).toBe(3500);
    await expect(db.query("INSERT INTO services (name, base_duration_minutes, price_minor) VALUES ('x', 10, -1)")).rejects.toThrow(/check constraint/);
  });

  it('change feed sequence numbers increase in commit order', async () => {
    const t1 = await ctx.pools.adminClient(S.dbName);
    const t2 = await ctx.pools.adminClient(S.dbName);
    try {
      await t1.query('BEGIN');
      const { rows: [a] } = await t1.query("INSERT INTO changes (entity, op) VALUES ('booking', 'insert') RETURNING seq");
      await t2.query('BEGIN');
      let bSeq: number | undefined;
      const p = t2.query("INSERT INTO changes (entity, op) VALUES ('booking', 'update') RETURNING seq").then((r) => {
        bSeq = Number(r.rows[0].seq);
      });
      await sleep(200);
      expect(bSeq).toBeUndefined(); // waits for t1 → can't commit a lower number later
      await t1.query('COMMIT');
      await p;
      await t2.query('COMMIT');
      expect(bSeq!).toBeGreaterThan(Number(a.seq));
      await expect(db.query('UPDATE changes SET op = $1', ['delete'])).rejects.toThrow(/append-only/);
    } finally {
      await t1.end();
      await t2.end();
    }
  });

  it('enforces core constraints (max 6 photos, break shapes, walk_in_only breaks)', async () => {
    await expect(db.query("INSERT INTO salon_photos (path, position) VALUES ('p', 7)")).rejects.toThrow();
    const [{ id: staffId }] = (await db.query('SELECT id FROM staff LIMIT 1')).rows;
    await db.query(
      "INSERT INTO breaks (staff_id, type, start_time, end_time) VALUES ($1, 'walk_in_only', '16:00', '18:00')",
      [staffId],
    );
    await db.query(
      "INSERT INTO breaks (staff_id, work_date, type, starts_at, ends_at) VALUES ($1, current_date, 'prayer', now(), now() + interval '20 min')",
      [staffId],
    );
    await expect(
      db.query("INSERT INTO breaks (staff_id, type, starts_at, ends_at) VALUES ($1, 'rest', now(), now() + interval '1 hour')", [staffId]),
    ).rejects.toThrow(/check constraint/);
  });
});

describe('tenant pools', () => {
  it('are created lazily per salon and evicted when idle', async () => {
    const ctx = await startApp();
    const S = await createSalon(ctx, 'Pool Salon');
    await ctx.close();
    const cfg = testConfig({ TENANT_POOL_IDLE_TTL_MS: '50' });
    const pools = new PoolManager(cfg);
    try {
      expect(pools.hasTenantPool(S.dbName)).toBe(false);
      await pools.tenantPool(S.dbName).query('SELECT 1');
      expect(pools.hasTenantPool(S.dbName)).toBe(true);
      expect(await pools.evictIdle(Date.now() + 10)).toBe(0);
      expect(await pools.evictIdle(Date.now() + 1_000)).toBe(1);
      expect(pools.hasTenantPool(S.dbName)).toBe(false);
      // Transparently recreated on next use.
      await pools.tenantPool(S.dbName).query('SELECT 1');
      expect(pools.tenantPoolCount()).toBe(1);
      expect(() => pools.tenantPool('bad-name; DROP')).toThrow();
    } finally {
      await pools.close();
    }
  });
});

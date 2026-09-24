import { randomUUID } from 'node:crypto';
import { Client } from 'pg';
import { salonQuery, startApp, TestContext } from './helpers';
import {
  at,
  auth,
  book,
  clock,
  closeQueueApp,
  dropCreatedSalons,
  event,
  heartbeat,
  isoAt,
  newCustomer,
  notifications,
  push,
  runScheduler,
  settle,
  setupQueueSalon,
  staffToday,
  T0,
} from './queue-helpers';

/** Round-2 fixes after the phase-10 verification (items 1–4; 5–7 live in config.spec / auth / review-fixes). */
describe('round 2 fixes', () => {
  let ctx: TestContext;
  beforeAll(async () => {
    ctx = await startApp();
  });
  afterAll(() => closeQueueApp(ctx));
  beforeEach(() => clock(ctx).set(T0));
  afterEach(() => dropCreatedSalons(ctx));

  const row = async (dbName: string, id: string) => (await salonQuery(ctx, dbName, 'SELECT * FROM bookings WHERE id = $1', [id]))[0];
  const current = async (token: string) => (await ctx.http().get('/v1/bookings/current').set(auth(token))).body;

  // ─── Item 1: a stale operational day is bounded by day_close_grace_minutes ─────────
  // T0 = Thursday 2026-03-05 10:00 (Riyadh). Shift 09:00–12:00 → default grace 6 h ends at 18:00 = at(480).
  for (const variant of ['salon closed on Fridays', 'barber working one day a week'] as const) {
    it(`item 1 (${variant}): the leftover booking is closed after the grace, no longer active, never called again`, async () => {
      const s = await setupQueueSalon(ctx, { opens: '09:00', closes: '12:00' });
      const b = s.barbers[0]!;
      const drop = variant === 'salon closed on Fridays' ? 'weekday = 5' : 'weekday <> 4';
      await salonQuery(ctx, s.dbName, `DELETE FROM work_schedules WHERE staff_id = $1 AND ${drop}`, [b.id]);
      const svc = [s.services.haircut];
      const [c1, c2, c3] = [await newCustomer(ctx, s), await newCustomer(ctx, s), await newCustomer(ctx, s)];
      const r1 = (await book(ctx, c1, { serviceIds: svc, kind: 'queue' })).body.id;
      const r2 = (await book(ctx, c2, { serviceIds: svc, kind: 'queue' })).body.id;
      const r3 = (await book(ctx, c3, { serviceIds: svc, kind: 'queue' })).body.id;
      await heartbeat(ctx, b);
      await push(ctx, b, [event(ctx, b, 'service_started', r1, {}, at(0))]);

      // 17:59 — after closing but within the grace: still the operational day (ق24).
      clock(ctx).set(at(479));
      await runScheduler(ctx, s);
      expect((await row(s.dbName, r3)).day_closed_at).toBeNull();
      expect((await current(c3.token)).booking?.id).toBe(r3);

      // 18:00 — shift end + 6 h: closed out (before the fix: only on Saturday 08:00 / next Thursday).
      clock(ctx).set(at(480));
      expect((await current(c3.token)).booking).toBeNull(); // never "current" once stale, even before the close-out
      await runScheduler(ctx, s);
      for (const id of [r2, r3]) expect(await row(s.dbName, id)).toMatchObject({ status: 'cancelled', cancel_reason: 'day_closed' });
      expect(await row(s.dbName, r1)).toMatchObject({ status: 'in_service', needs_review: true });
      await settle(ctx);
      expect(await notifications(ctx, s, "recipient_id = $1 AND type = 'cancelled_closing'", [c3.id])).toHaveLength(1);
      // No longer counted as the customer's active booking.
      const [{ n }] = await salonQuery(ctx, s.dbName, "SELECT count(*)::int AS n FROM bookings WHERE customer_id = $1 AND status IN ('waiting', 'called', 'in_service') AND day_closed_at IS NULL", [c3.id]);
      expect(n).toBe(0);

      // The scheduler neither calls nor notifies for it any more.
      const before = (await notifications(ctx, s, "type IN ('called', 'eta_changed')")).length;
      for (const m of [540, 720, 1000]) {
        clock(ctx).set(at(m));
        await runScheduler(ctx, s);
      }
      expect((await notifications(ctx, s, "type IN ('called', 'eta_changed')")).length).toBe(before);
      expect((await row(s.dbName, r3)).status).toBe('cancelled');
      const today = await staffToday(ctx, b);
      expect(today.queue).toEqual([]);
    });
  }

  it('item 1: day_close_grace_minutes is a salon setting (60–720, default 360)', async () => {
    const s = await setupQueueSalon(ctx);
    const m = auth(s.manager.accessToken);
    expect((await ctx.http().get('/v1/manager/settings').set(m)).body.dayCloseGraceMinutes).toBe(360);
    expect((await ctx.http().put('/v1/manager/settings').set(m).send({ dayCloseGraceMinutes: 59 })).status).toBe(400);
    expect((await ctx.http().put('/v1/manager/settings').set(m).send({ dayCloseGraceMinutes: 721 })).status).toBe(400);
    expect((await ctx.http().put('/v1/manager/settings').set(m).send({ dayCloseGraceMinutes: 90 })).body.dayCloseGraceMinutes).toBe(90);
  });

  // ─── Item 2: ق23 never influenced by client-supplied "seen" ──────────────────────
  it('item 2: with a 1-minute margin, seen = projection + 5 min cannot make a postponement exempt', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const m = auth(s.manager.accessToken);
    await ctx.http().put('/v1/manager/settings').set(m).send({ etaChangeNotifyMinutes: 1 }).expect(200);
    const c = await newCustomer(ctx, s);
    const id = (await book(ctx, c, { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    await heartbeat(ctx, b);
    // Within the 5-minute tolerance → recorded as the ق5 reference…
    await ctx.http().post(`/v1/bookings/${id}/seen`).set(auth(c.token)).send({ eta: isoAt(5) }).expect(204);
    expect((await row(s.dbName, id)).last_shown_expected_start).toEqual(new Date(at(5)));
    // …the scheduler calls him / sends the ق5 notice at the real time (at(0)).
    await runScheduler(ctx, s);
    const called = await row(s.dbName, id);
    expect(called.status).toBe('called');
    expect(called.told_expected_start).toEqual(new Date(at(0)));
    expect(called.reference_before_advance).toBeNull(); // the client's +5 min is not a pre-advance reference
    // …but the postponement is counted: the server never told him a later time.
    const p = await push(ctx, b, [event(ctx, b, 'postponed', id, { steps: 1 })]);
    expect(p[0]).toEqual({ eventId: expect.any(String), result: 'applied' });
    expect((await row(s.dbName, id)).postpone_used).toBe(true);
    expect((await push(ctx, b, [event(ctx, b, 'no_show', id)]))[0]!.result).toBe('applied');
  });

  it('item 2: a genuine server-side advance still exempts (ق23 unchanged)', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const m = auth(s.manager.accessToken);
    await ctx.http().put('/v1/manager/settings').set(m).send({ etaChangeNotifyMinutes: 1 }).expect(200);
    const svc = [s.services.haircut];
    const [c1, c2] = [await newCustomer(ctx, s), await newCustomer(ctx, s)];
    const r1 = (await book(ctx, c1, { serviceIds: svc, kind: 'queue' })).body.id;
    const r2 = (await book(ctx, c2, { serviceIds: svc, kind: 'queue' })).body.id; // told at(30)
    await heartbeat(ctx, b);
    await ctx.http().post(`/v1/bookings/${r1}/cancel`).set(auth(c1.token)).set('Idempotency-Key', randomUUID()).expect(200);
    await runScheduler(ctx, s); // r2 advanced to at(0) and called
    expect((await row(s.dbName, r2)).reference_before_advance).toEqual(new Date(at(30)));
    const p = await push(ctx, b, [event(ctx, b, 'postponed', r2, { steps: 1 })]);
    expect(p[0]).toMatchObject({ result: 'applied', reason: 'POSTPONEMENT_NOT_COUNTED' });
  });

  // ─── Item 3: lock order day row → breaks → change_counter ─────────────────────────
  it('item 3: breaks rows and the change counter are never locked before the barber-day row (scheduler + device)', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const svc = [s.services.haircut];
    // An open device break left over from yesterday, and an offer about to expire (releasing it emits changes).
    await salonQuery(ctx, s.dbName, `INSERT INTO barber_days (staff_id, work_date) VALUES ($1, '2026-03-04') ON CONFLICT DO NOTHING`, [b.id]);
    await salonQuery(ctx, s.dbName, `INSERT INTO breaks (staff_id, work_date, type, starts_at, ends_at, open, created_by_staff_id) VALUES ($1, '2026-03-04', 'rest', $2, $3, true, $1)`, [
      b.id,
      new Date(at(-24 * 60)),
      new Date(at(-24 * 60 + 15)),
    ]);
    await book(ctx, await newCustomer(ctx, s), { serviceIds: svc, kind: 'queue' });
    const c = await newCustomer(ctx, s);
    const q = await ctx.http().post('/v1/bookings/quote').set(auth(c.token)).set('Idempotency-Key', randomUUID()).send({ serviceIds: svc, barberId: b.id, kind: 'requested', requestedAt: isoAt(10) });
    expect(q.body.outcome).toBe('offer');
    await heartbeat(ctx, b);
    clock(ctx).set(at(5)); // the offer (held 2 min) has expired

    const txs = await recordTransactions(async () => {
      await runScheduler(ctx, s);
    });
    assertLockOrder(txs);
    expect((await salonQuery(ctx, s.dbName, "SELECT open FROM breaks WHERE work_date = '2026-03-04'"))[0].open).toBe(false);
    await heartbeat(ctx, b);

    // The device path: another expired offer, a stale open break, then break_started.
    await salonQuery(ctx, s.dbName, "UPDATE breaks SET open = true WHERE work_date = '2026-03-04'");
    const q2 = await ctx.http().post('/v1/bookings/quote').set(auth(c.token)).set('Idempotency-Key', randomUUID()).send({ serviceIds: svc, barberId: b.id, kind: 'requested', requestedAt: isoAt(15) });
    expect(q2.body).toMatchObject({ outcome: 'offer' });
    clock(ctx).set(at(8)); // that offer expired too (released by the first locked operation)
    const txs2 = await recordTransactions(async () => {
      expect((await push(ctx, b, [event(ctx, b, 'break_started', null, { kind: 'rest' })]))[0]!.result).toBe('applied');
    });
    assertLockOrder(txs2);
    expect(txs2.some((t) => t.some((sql) => /FROM breaks .*FOR UPDATE/.test(sql)))).toBe(true);
  });

  it('item 3: concurrent break events and scheduler runs never deadlock', async () => {
    const s = await setupQueueSalon(ctx, { barbers: 2 });
    const svc = [s.services.haircut];
    for (const b of s.barbers) {
      await book(ctx, await newCustomer(ctx, s), { serviceIds: svc, barberId: b.id, kind: 'queue' });
      await heartbeat(ctx, b);
      await salonQuery(ctx, s.dbName, `INSERT INTO breaks (staff_id, work_date, type, starts_at, ends_at, open, created_by_staff_id) VALUES ($1, '2026-03-04', 'rest', $2, $3, true, $1)`, [
        b.id,
        new Date(at(-24 * 60)),
        new Date(at(-24 * 60 + 15)),
      ]);
    }
    const deadlocks = await countDeadlocks(async () => {
      for (let round = 0; round < 4; round++) {
        clock(ctx).set(at(10 + round * 10));
        await Promise.all([
          runScheduler(ctx, s),
          ...s.barbers.map((b) => push(ctx, b, [event(ctx, b, round % 2 ? 'break_ended' : 'break_started', null, { kind: 'rest' })])),
          runScheduler(ctx, s),
        ]);
      }
    });
    expect(deadlocks).toBe(0);
  });

  // ─── Item 4: unfinished services from a closed day ─────────────────────────────────
  it('item 4: unfinished in-service bookings of a closed day are shown to the barber and the manager; finished via sync or resolved by the manager', async () => {
    const s = await setupQueueSalon(ctx, { opens: '09:00', closes: '12:00', barbers: 3 });
    const [b1, b2, b3] = s.barbers as [typeof s.barbers[0], typeof s.barbers[0], typeof s.barbers[0]];
    const m = auth(s.manager.accessToken);
    const svc = [s.services.haircut];
    const ids: string[] = [];
    for (const b of [b1, b2, b3]) {
      const id = (await book(ctx, await newCustomer(ctx, s), { serviceIds: svc, barberId: b.id, kind: 'queue' })).body.id;
      await push(ctx, b, [event(ctx, b, 'service_started', id, {}, at(0))]);
      ids.push(id);
    }
    const [r1, r2, r3] = ids as [string, string, string];
    clock(ctx).set(at(480)); // 18:00 — grace over: day closed, all three left in service
    await runScheduler(ctx, s);
    for (const id of ids) expect(await row(s.dbName, id)).toMatchObject({ status: 'in_service', needs_review: true });

    // Barber: GET /staff/today lists it.
    const today = await staffToday(ctx, b1);
    expect(today.unfinishedFromPreviousDay.map((x: { id: string }) => x.id)).toEqual([r1]);
    expect(today.unfinishedFromPreviousDay[0]).toMatchObject({ status: 'in_service', needsReview: true, workDate: '2026-03-05' });
    // Manager: queues (per barber and overall) and pending items.
    const queues = (await ctx.http().get('/v1/manager/queues').set(m)).body;
    expect(queues.barbers.find((x: { id: string }) => x.id === b2.id).unfinishedFromPreviousDay.map((x: { id: string }) => x.id)).toEqual([r2]);
    expect(queues.unfinishedFromPreviousDay.map((x: { id: string }) => x.id).sort()).toEqual([...ids].sort());
    const pending = async () => (await ctx.http().get('/v1/manager/reports?from=2026-03-05&to=2026-03-05').set(m)).body.pendingItems;
    expect((await pending()).unfinishedServices).toBe(3);

    // Barber finishes it via sync, then confirms the payment.
    clock(ctx).set(at(481));
    const fin = await push(ctx, b1, [event(ctx, b1, 'service_finished', r1, {}, at(481)), event(ctx, b1, 'payment_confirmed', r1, {})]);
    expect(fin.map((x) => x.result)).toEqual(['applied', 'applied']);
    expect(await row(s.dbName, r1)).toMatchObject({ status: 'done' });
    expect((await salonQuery(ctx, s.dbName, 'SELECT status FROM payments WHERE booking_id = $1', [r1]))[0].status).toBe('confirmed');
    expect((await salonQuery(ctx, s.dbName, 'SELECT excluded, exclusion_reason FROM duration_samples WHERE booking_id = $1', [r1]))[0]).toEqual({ excluded: true, exclusion_reason: 'after_day_close' });
    expect((await staffToday(ctx, b1)).unfinishedFromPreviousDay).toEqual([]);

    // Manager: guards.
    const resolve = (id: string, body: Record<string, unknown>, token = s.manager.accessToken) =>
      ctx.http().post(`/v1/manager/bookings/${id}/resolve`).set(auth(token)).set('Idempotency-Key', randomUUID()).send(body);
    expect((await resolve(r2, { action: 'finish', actualEnd: isoAt(-5) })).body.error.code).toBe('INVALID_END_TIME');
    expect((await resolve(r1, { action: 'cancel', reason: 'x' })).body.error.code).toBe('BOOKING_NOT_UNFINISHED');
    expect((await resolve(r2, { action: 'finish' })).status).toBe(400);
    expect((await resolve(r2, { action: 'finish', actualEnd: isoAt(40) }, b2.token)).status).toBe(403);

    // Manager finishes r2 with the real end time → payment awaiting confirmation; the barber confirms it.
    const done = await resolve(r2, { action: 'finish', actualEnd: isoAt(40) });
    expect(done.status).toBe(200);
    expect(done.body).toMatchObject({ id: r2, status: 'done', actualEnd: new Date(at(40)).toISOString() });
    expect((await salonQuery(ctx, s.dbName, 'SELECT status, amount_minor FROM payments WHERE booking_id = $1', [r2]))[0]).toEqual({ status: 'awaiting_confirmation', amount_minor: '5000' });
    expect((await push(ctx, b2, [event(ctx, b2, 'payment_confirmed', r2, {})]))[0]!.result).toBe('applied');

    // Manager cancels r3 with a reason.
    const cancelled = await resolve(r3, { action: 'cancel', reason: 'غادر الزبون دون إكمال' });
    expect(cancelled.body).toMatchObject({ status: 'cancelled' });
    expect(await row(s.dbName, r3)).toMatchObject({ status: 'cancelled', cancel_reason: 'manager: غادر الزبون دون إكمال' });

    expect((await pending()).unfinishedServices).toBe(0);
    expect(await salonQuery(ctx, s.dbName, "SELECT 1 FROM sync_conflicts WHERE kind = 'unfinished_at_day_close' AND resolved_at IS NULL")).toEqual([]);
    expect(await salonQuery(ctx, s.dbName, "SELECT 1 FROM audit_log WHERE action = 'booking.unfinished_resolved'")).toHaveLength(2);
    expect((await ctx.http().get('/v1/manager/queues').set(m)).body.unfinishedFromPreviousDay).toEqual([]);
  });
});

// ─── SQL recording helpers (item 3) ───────────────────────────────────────────────────

/** Runs `fn` and returns the SQL of every transaction it ran, per connection, BEGIN…COMMIT/ROLLBACK. */
async function recordTransactions(fn: () => Promise<void>): Promise<string[][]> {
  const open = new Map<object, string[]>();
  const done: string[][] = [];
  const original = Client.prototype.query;
  const spy = jest.spyOn(Client.prototype, 'query').mockImplementation(function (this: object, ...args: unknown[]) {
    const first = args[0] as string | { text?: string };
    const sql = (typeof first === 'string' ? first : first?.text ?? '').replace(/\s+/g, ' ').trim();
    if (sql === 'BEGIN') open.set(this, []);
    else if (sql === 'COMMIT' || sql === 'ROLLBACK') {
      const t = open.get(this);
      if (t) done.push(t);
      open.delete(this);
    } else open.get(this)?.push(sql);
    return (original as (...a: unknown[]) => unknown).apply(this, args);
  } as never);
  try {
    await fn();
  } finally {
    spy.mockRestore();
  }
  return done;
}

/** Every transaction that locks `breaks` rows first holds a barber-day row lock, and emits changes only after. */
function assertLockOrder(txs: string[][]): void {
  const withBreaks = txs.filter((t) => t.some((sql) => /FROM breaks .*FOR UPDATE/.test(sql)));
  expect(withBreaks.length).toBeGreaterThan(0);
  for (const t of withBreaks) {
    const day = t.findIndex((sql) => /FROM barber_days .*FOR UPDATE/.test(sql));
    const brk = t.findIndex((sql) => /FROM breaks .*FOR UPDATE/.test(sql));
    const emit = t.findIndex((sql) => sql.startsWith('INSERT INTO changes'));
    expect(day).toBeGreaterThanOrEqual(0);
    expect(day).toBeLessThan(brk);
    if (emit >= 0) expect(brk).toBeLessThan(emit);
  }
}

/** Counts deadlock errors (40P01) raised by the database while `fn` runs (PostCommit would retry them). */
async function countDeadlocks(fn: () => Promise<void>): Promise<number> {
  let n = 0;
  const original = Client.prototype.query;
  const spy = jest.spyOn(Client.prototype, 'query').mockImplementation(function (this: object, ...args: unknown[]) {
    const out = (original as (...a: unknown[]) => unknown).apply(this, args);
    if (out && typeof (out as Promise<unknown>).catch === 'function') {
      (out as Promise<unknown>).catch((e: { code?: string }) => {
        if (e?.code === '40P01') n++;
      });
    }
    return out;
  } as never);
  try {
    await fn();
  } finally {
    spy.mockRestore();
  }
  return n;
}

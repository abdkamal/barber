import { randomUUID } from 'node:crypto';
import sharp from 'sharp';
import { SchedulerService } from '../src/scheduler/scheduler.service';
import { createSalon, randomPhone, registerCustomer, salonQuery, startApp, staffLogin, testConfig, TestContext } from './helpers';
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

/** Phase 6 review fixes (C1, I1/H1, I6, minor; H2, H3, M1, M4, L1, L3, L5, L8). */
describe('review fixes', () => {
  let ctx: TestContext;
  beforeAll(async () => {
    ctx = await startApp();
  });
  afterAll(() => closeQueueApp(ctx));
  beforeEach(() => clock(ctx).set(T0));
  afterEach(() => dropCreatedSalons(ctx));

  const walkIn = (token: string, body: Record<string, unknown>) =>
    ctx.http().post('/v1/staff/walk-ins').set(auth(token)).set('Idempotency-Key', randomUUID()).send(body);
  const current = async (token: string) => (await ctx.http().get('/v1/bookings/current').set(auth(token))).body;
  const status = async (dbName: string, id: string) => (await salonQuery(ctx, dbName, 'SELECT * FROM bookings WHERE id = $1', [id]))[0];

  // ─── C1 ────────────────────────────────────────────────────────────────────────────
  it('C1: after closing the day stays operational while customers are served; next day it is closed out', async () => {
    const s = await setupQueueSalon(ctx, { opens: '09:00', closes: '12:00' }); // T0 = 10:00, closing = at(120)
    const b = s.barbers[0]!;
    const svc = [s.services.haircut];
    const [c1, c2, c3] = [await newCustomer(ctx, s), await newCustomer(ctx, s), await newCustomer(ctx, s)];
    const r1 = (await book(ctx, c1, { serviceIds: svc, kind: 'queue' })).body.id;
    const r2 = (await book(ctx, c2, { serviceIds: svc, kind: 'queue' })).body.id;
    const r3 = (await book(ctx, c3, { serviceIds: svc, kind: 'queue' })).body.id;
    await heartbeat(ctx, b);
    await push(ctx, b, [event(ctx, b, 'service_started', r1, {}, at(0))]);

    // 12:05 — past closing, the first service overran; two customers still wait.
    clock(ctx).set(at(125));
    const hb = await heartbeat(ctx, b);
    expect(hb).toMatchObject({ workDate: '2026-03-05', state: 'connected' });
    const today = await staffToday(ctx, b);
    expect(today.day?.workDate).toBe('2026-03-05');
    expect(today.queue.map((x: { id: string }) => x.id)).toEqual([r1, r2, r3]);
    expect(today.closingWarnings).toEqual(expect.arrayContaining([r2, r3]));
    // Nothing NEW is accepted after closing.
    expect((await walkIn(b.token, { name: 'حاضر', phone: '0555000999', serviceIds: svc })).body.error.code).toBe('NOT_WORKING_NOW');
    expect((await book(ctx, await newCustomer(ctx, s), { serviceIds: svc, kind: 'queue' })).body.error.code).toBe('BOOKING_CLOSED');
    // Finishing and payment still work; ق24 decision recorded.
    const done = await push(ctx, b, [
      event(ctx, b, 'service_finished', r1, {}, at(124)),
      event(ctx, b, 'payment_confirmed', r1, {}),
      event(ctx, b, 'closing_decision', r2, { decision: 'serve_late' }),
    ]);
    expect(done.map((x) => x.result)).toEqual(['applied', 'applied', 'applied']);
    // The scheduler keeps working this day: r2 is called.
    await runScheduler(ctx, s);
    expect((await status(s.dbName, r2)).status).toBe('called');
    const q = await ctx.http().get('/v1/manager/queues').set(auth(s.manager.accessToken));
    expect(q.body.barbers.find((x: { id: string }) => x.id === b.id).day.workDate).toBe('2026-03-05');
    clock(ctx).set(at(126));
    expect((await push(ctx, b, [event(ctx, b, 'service_started', r2, {}, at(126))]))[0]!.result).toBe('applied');

    // Next morning 08:00 (booking window of the next day opens at 09:00 − 60 min).
    clock(ctx).set(at(22 * 60));
    // Even before the scheduler closes it, a past day's booking is not "current".
    expect((await current(c3.token)).booking).toBeNull();
    await runScheduler(ctx, s);
    const x3 = await status(s.dbName, r3);
    expect(x3).toMatchObject({ status: 'cancelled', cancel_reason: 'day_closed' });
    expect(x3.day_closed_at).not.toBeNull();
    const x2 = await status(s.dbName, r2);
    expect(x2).toMatchObject({ status: 'in_service', needs_review: true });
    expect(await salonQuery(ctx, s.dbName, "SELECT 1 FROM sync_conflicts WHERE kind = 'unfinished_at_day_close' AND booking_id = $1", [r2])).toHaveLength(1);
    await settle(ctx);
    expect(await notifications(ctx, s, "recipient_id = $1 AND type = 'cancelled_closing'", [c3.id])).toHaveLength(1);
    expect((await current(c2.token)).booking).toBeNull();
    const next = await staffToday(ctx, b);
    expect(next.day.workDate).toBe('2026-03-06');
    expect(next.queue).toEqual([]);
    // The closed-out booking no longer counts as the customer's active booking.
    expect((await book(ctx, c2, { serviceIds: svc, kind: 'queue' })).status).toBe(201);
  });

  // ─── I1 / H1 ───────────────────────────────────────────────────────────────────────
  it('H1: a far-future "seen" eta is ignored — it cannot make a postponement exempt and prevent the no-show', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const c = await newCustomer(ctx, s);
    const id = (await book(ctx, c, { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    await heartbeat(ctx, b);
    const far = await ctx.http().post(`/v1/bookings/${id}/seen`).set(auth(c.token)).send({ eta: isoAt(300) });
    expect(far.status).toBe(204);
    expect((await status(s.dbName, id)).last_shown_expected_start).toEqual(new Date(at(0)));
    // A value close to the server's projection is recorded.
    await ctx.http().post(`/v1/bookings/${id}/seen`).set(auth(c.token)).send({ eta: isoAt(2) }).expect(204);
    expect((await status(s.dbName, id)).last_shown_expected_start).toEqual(new Date(at(2)));
    const p = await push(ctx, b, [event(ctx, b, 'postponed', id, { steps: 1 })]);
    expect(p[0]).toEqual({ eventId: expect.any(String), result: 'applied' });
    expect((await status(s.dbName, id)).postpone_used).toBe(true);
    expect((await push(ctx, b, [event(ctx, b, 'no_show', id)]))[0]!.result).toBe('applied');
  });

  it('I1: ق23 still applies with the scheduler running (the call/notice does not erase the pre-advance reference)', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const svc = [s.services.haircut];
    const [c1, c2, c3] = [await newCustomer(ctx, s), await newCustomer(ctx, s), await newCustomer(ctx, s)];
    const r1 = (await book(ctx, c1, { serviceIds: svc, kind: 'queue' })).body.id;
    const r2 = (await book(ctx, c2, { serviceIds: svc, kind: 'queue' })).body.id;
    const r3 = (await book(ctx, c3, { serviceIds: svc, kind: 'queue' })).body.id;
    await heartbeat(ctx, b);
    for (const [c, id] of [[c1, r1], [c2, r2]] as const) {
      await ctx.http().post(`/v1/bookings/${id}/cancel`).set(auth(c.token)).set('Idempotency-Key', randomUUID()).expect(200);
    }
    await runScheduler(ctx, s); // r3 (known at +60) is now first → called at once
    const called = await status(s.dbName, r3);
    expect(called.status).toBe('called');
    expect(called.reference_before_advance).toEqual(new Date(at(60)));
    clock(ctx).set(at(5));
    await heartbeat(ctx, b);
    const p = await push(ctx, b, [event(ctx, b, 'postponed', r3, { steps: 1 })]);
    expect(p[0]).toMatchObject({ result: 'applied', reason: 'POSTPONEMENT_NOT_COUNTED' });
    expect((await status(s.dbName, r3)).postpone_used).toBe(false);
  });

  // ─── I6 ────────────────────────────────────────────────────────────────────────────
  it('I6: manager breaks/absences run in the locked day: queue re-committed with a reason, devices told', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const m = auth(s.manager.accessToken);
    const svc = [s.services.haircut];
    await book(ctx, await newCustomer(ctx, s), { serviceIds: svc, kind: 'queue' });
    const r2 = (await book(ctx, await newCustomer(ctx, s), { serviceIds: svc, kind: 'queue' })).body.id;
    await heartbeat(ctx, b);
    const seq0 = Number((await salonQuery(ctx, s.dbName, 'SELECT value FROM change_counter'))[0].value);
    const br = await ctx.http().post('/v1/manager/breaks').set(m).send({ staffId: b.id, type: 'rest', workDate: '2026-03-05', startsAt: isoAt(30), endsAt: isoAt(55) });
    expect(br.status).toBe(201);
    expect((await status(s.dbName, r2)).projected_start).toEqual(new Date(at(55)));
    const ch = await salonQuery(ctx, s.dbName, 'SELECT type, data FROM changes WHERE seq > $1 AND staff_id = $2 ORDER BY seq', [seq0, b.id]);
    expect(ch.map((c) => c.type)).toEqual(expect.arrayContaining(['queue_updated', 'breaks_changed']));
    expect(ch.find((c) => c.type === 'queue_updated').data.reason).toBe('schedule_changed');
    expect(await salonQuery(ctx, s.dbName, "SELECT 1 FROM booking_events WHERE booking_id = $1 AND type = 'eta_changed' AND reason = 'schedule_changed'", [r2])).toHaveLength(1);
    await ctx.http().delete(`/v1/manager/breaks/${br.body[0].id}`).set(m).expect(200);
    expect((await status(s.dbName, r2)).projected_start).toEqual(new Date(at(30)));

    const abs = await ctx.http().post('/v1/manager/absences').set(m).send({ staffId: b.id, workDate: '2026-03-05' });
    expect(abs.status).toBe(201);
    const [day] = await salonQuery(ctx, s.dbName, "SELECT state FROM barber_days WHERE staff_id = $1 AND work_date = '2026-03-05'", [b.id]);
    expect(day.state).toBe('absent');
    const ds = await salonQuery(ctx, s.dbName, "SELECT data FROM changes WHERE type = 'day_state' AND staff_id = $1 ORDER BY seq DESC LIMIT 1", [b.id]);
    expect(ds[0].data).toMatchObject({ workDate: '2026-03-05', state: 'absent_today' });
    await ctx.http().delete(`/v1/manager/absences/${abs.body.id}`).set(m).expect(200);
    const ds2 = await salonQuery(ctx, s.dbName, "SELECT data FROM changes WHERE type = 'day_state' AND staff_id = $1 ORDER BY seq DESC LIMIT 1", [b.id]);
    expect(ds2[0].data.state).toBe('connected');
    expect(ctx.app.get(SchedulerService).nextDue(s.id)).toBe(0); // poked
  });

  // ─── Minor ─────────────────────────────────────────────────────────────────────────
  it('an open device break is closed at shift end and never blocks the next day', async () => {
    const s = await setupQueueSalon(ctx, { opens: '09:00', closes: '12:00' });
    const b = s.barbers[0]!;
    clock(ctx).set(at(100));
    expect((await push(ctx, b, [event(ctx, b, 'break_started', null, { kind: 'rest' })]))[0]!.result).toBe('applied');
    clock(ctx).set(at(130));
    await runScheduler(ctx, s);
    const [br] = await salonQuery(ctx, s.dbName, 'SELECT open, ends_at FROM breaks WHERE staff_id = $1', [b.id]);
    expect(br).toEqual({ open: false, ends_at: new Date(at(120)) });
    // Directly on the device (scheduler not run): a stale open break of an earlier day is closed first.
    await salonQuery(ctx, s.dbName, 'UPDATE breaks SET open = true WHERE staff_id = $1', [b.id]);
    clock(ctx).set(at(24 * 60)); // next day 10:00
    expect((await push(ctx, b, [event(ctx, b, 'break_started', null, { kind: 'rest' })]))[0]!.result).toBe('applied');
  });

  it('ق22: the skipped (called) customer is no longer marked called', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const id = (await book(ctx, await newCustomer(ctx, s), { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    await heartbeat(ctx, b);
    await runScheduler(ctx, s);
    expect((await status(s.dbName, id)).called_at).not.toBeNull();
    const w = await walkIn(b.token, { name: 'زبون حاضر', phone: '0555000111', serviceIds: [s.services.beard] });
    await push(ctx, b, [event(ctx, b, 'service_started', w.body.id)]);
    expect(await status(s.dbName, id)).toMatchObject({ status: 'waiting', called_at: null });
  });

  it('payments: the server price is expected; the device amount is recorded and a difference flagged; reports show both', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const m = auth(s.manager.accessToken);
    const id = (await book(ctx, await newCustomer(ctx, s), { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    await push(ctx, b, [event(ctx, b, 'service_started', id, {}, at(0))]);
    clock(ctx).set(at(30));
    await push(ctx, b, [event(ctx, b, 'service_finished', id, {}, at(30))]);
    const conf = await push(ctx, b, [event(ctx, b, 'payment_confirmed', id, { amount: 4000 })]);
    expect(conf[0]).toMatchObject({ result: 'applied', reason: 'AMOUNT_DIFFERS_FROM_PRICE' });
    const [p] = await salonQuery(ctx, s.dbName, 'SELECT amount_minor, confirmed_amount_minor, discrepancy FROM payments WHERE booking_id = $1', [id]);
    expect(p).toEqual({ amount_minor: '5000', confirmed_amount_minor: '4000', discrepancy: true });
    const pays = await ctx.http().get('/v1/staff/payments').set(auth(b.token));
    expect(pays.body[0]).toMatchObject({ amountCents: 5000, confirmedAmountCents: 4000, discrepancy: true, status: 'confirmed' });

    // A second visit with an approximate start: excluded from duration-vs-base.
    const id2 = (await book(ctx, await newCustomer(ctx, s), { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    await push(ctx, b, [event(ctx, b, 'service_started', id2, {}, at(31), { approximate: true })]);
    clock(ctx).set(at(80));
    await push(ctx, b, [event(ctx, b, 'service_finished', id2, {}, at(80))]);

    const rep = (await ctx.http().get('/v1/manager/reports?from=2026-03-05&to=2026-03-05').set(m)).body;
    expect(rep.revenue.perBarber[0]).toMatchObject({ confirmed: 4000, expectedConfirmed: 5000, awaiting: 5000, discrepancies: 1 });
    expect(rep.topServices[0]).toMatchObject({ times: 2, revenue: 4000 });
    expect(rep.durationVsBase[0]).toMatchObject({ samples: 1, avgActualMinutes: 30 });
    expect(rep.pendingItems.paymentDiscrepancies).toBe(1);
  });

  it('reports: a phone whose extra walk-in record is linked to an active account is not a dispute', async () => {
    const s = await setupQueueSalon(ctx);
    const phone = randomPhone();
    const acct = await registerCustomer(ctx, s.code, phone);
    const [w1] = await salonQuery(ctx, s.dbName, "INSERT INTO customers (name, phone, status) VALUES ('أ', $1, 'active') RETURNING id", [phone]);
    await salonQuery(ctx, s.dbName, "INSERT INTO customers (name, phone, status) VALUES ('ب', $1, 'active')", [phone]);
    const m = auth(s.manager.accessToken);
    const before = (await ctx.http().get('/v1/manager/reports?from=2026-03-05&to=2026-03-05').set(m)).body.pendingItems.phoneDisputes;
    await salonQuery(ctx, s.dbName, 'UPDATE customers SET linked_walk_in_id = $2 WHERE id = $1', [acct.body.account.id, w1.id]);
    const after = (await ctx.http().get('/v1/manager/reports?from=2026-03-05&to=2026-03-05').set(m)).body.pendingItems.phoneDisputes;
    expect(before).toBe(1);
    expect(after).toBe(0);
    expect((await ctx.http().get('/v1/manager/phone-disputes').set(m)).body).toEqual([]);
  });

  // ─── H2 ────────────────────────────────────────────────────────────────────────────
  it('H2: a walk-in match at registration is only proposed; effective on approval; unlink / release / reassign', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const m = auth(s.manager.accessToken);
    await ctx.http().put('/v1/manager/settings').set(m).send({ requireAccountApproval: true }).expect(200);
    await heartbeat(ctx, b);
    const phone = randomPhone();
    const w = await walkIn(b.token, { name: 'علي', phone, serviceIds: [s.services.haircut] });
    await push(ctx, b, [event(ctx, b, 'service_started', w.body.id, {}, at(0))]);
    clock(ctx).set(at(30));
    await push(ctx, b, [event(ctx, b, 'service_finished', w.body.id, {}, at(30))]);
    const walkInId = w.body.customerId;

    const reg = await registerCustomer(ctx, s.code, phone);
    expect(reg.body.account.status).toBe('pending');
    const acctId = reg.body.account.id;
    expect((await salonQuery(ctx, s.dbName, 'SELECT linked_walk_in_id, proposed_walk_in_id FROM customers WHERE id = $1', [acctId]))[0]).toEqual({
      linked_walk_in_id: null,
      proposed_walk_in_id: walkInId,
    });
    const hist = () => ctx.http().get('/v1/customer/history').set(auth(reg.body.accessToken));
    expect((await hist()).body).toEqual([]);
    const disputes = (await ctx.http().get('/v1/manager/phone-disputes').set(m)).body;
    expect(disputes).toEqual([expect.objectContaining({ phone, accountId: acctId, accountStatus: 'pending', proposedWalkInId: walkInId })]);
    // A new walk-in with that phone does not auto-link to the pending account.
    await walkIn(b.token, { name: 'علي', phone, serviceIds: [s.services.beard] });
    expect((await salonQuery(ctx, s.dbName, 'SELECT linked_walk_in_id FROM customers WHERE id = $1', [acctId]))[0].linked_walk_in_id).toBeNull();

    await ctx.http().post(`/v1/manager/customers/${acctId}/approve`).set(m).expect(200);
    expect((await salonQuery(ctx, s.dbName, 'SELECT linked_walk_in_id FROM customers WHERE id = $1', [acctId]))[0].linked_walk_in_id).toBe(walkInId);
    expect((await hist()).body.map((x: { id: string }) => x.id)).toContain(w.body.id);

    await ctx.http().post(`/v1/manager/customers/${acctId}/unlink-walkin`).set(m).expect(200);
    expect((await hist()).body).toEqual([]);
    expect(await salonQuery(ctx, s.dbName, "SELECT 1 FROM audit_log WHERE action = 'customer.walkin_unlinked' AND target_id = $1", [acctId])).toHaveLength(1);

    // Release: the account is suspended and the number is free for its real owner.
    await ctx.http().post(`/v1/manager/customers/${acctId}/release-phone`).set(m).expect(200);
    expect((await hist()).status).toBe(401);
    const owner = await registerCustomer(ctx, s.code, phone, 'real-owner-pass');
    expect(owner.status).toBe(201);
    expect(owner.body.account.id).not.toBe(acctId);
    // Reassign the released account another number.
    const other = randomPhone();
    const re = await ctx.http().put(`/v1/manager/customers/${acctId}/phone`).set(m).send({ phone: other });
    expect(re.status).toBe(200);
    expect(re.body).toMatchObject({ phone: other, phone_released_at: null });
    const taken = await ctx.http().put(`/v1/manager/customers/${acctId}/phone`).set(m).send({ phone });
    expect(taken.body.error.code).toBe('PHONE_IN_USE');
  });

  // ─── H3 ────────────────────────────────────────────────────────────────────────────
  it('H3: a salon that is not active cannot upload images', async () => {
    const pending = await createSalon(ctx, 'صالون جديد', { activate: false });
    const png = await sharp({ create: { width: 8, height: 8, channels: 3, background: { r: 1, g: 2, b: 3 } } }).png().toBuffer();
    const r = await ctx.http().post('/v1/manager/photos').set(auth(pending.manager.accessToken)).attach('file', png, 'a.png');
    expect(r.status).toBe(409);
    expect(r.body.error.code).toBe('SALON_NOT_ACTIVE');
    const logo = await ctx.http().post('/v1/manager/profile/logo').set(auth(pending.manager.accessToken)).attach('file', png, 'a.png');
    expect(logo.body.error.code).toBe('SALON_NOT_ACTIVE');
    await ctx.vendor.cleanupPending(1, false, Date.now() + 2 * 86_400_000);
  });

  // ─── M4 ────────────────────────────────────────────────────────────────────────────
  it('M4: junk events are rejected before DB work with ONE conflict row; state-machine conflicts are capped per batch', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const junk = Array.from({ length: 50 }, () => event(ctx, b, 'teleport', null));
    const out = await push(ctx, b, junk);
    expect(new Set(out.map((x) => `${x.result}:${x.reason}`))).toEqual(new Set(['rejected:UNKNOWN_EVENT_TYPE']));
    expect(await salonQuery(ctx, s.dbName, 'SELECT kind FROM sync_conflicts')).toEqual([{ kind: 'rejected_events' }]);
    expect((await push(ctx, b, junk.slice(0, 3))).map((x) => x.result)).toEqual(['duplicate', 'duplicate', 'duplicate']);

    await salonQuery(ctx, s.dbName, 'DELETE FROM sync_conflicts');
    const missing = Array.from({ length: 30 }, () => event(ctx, b, 'no_show', randomUUID()));
    const out2 = await push(ctx, b, missing);
    expect(out2.every((x) => x.result === 'rejected' && x.reason === 'BOOKING_NOT_FOUND')).toBe(true);
    const kinds = (await salonQuery(ctx, s.dbName, 'SELECT kind, details FROM sync_conflicts')).map((r) => r.kind);
    expect(kinds.filter((k) => k === 'rejected_event')).toHaveLength(10);
    expect(kinds.filter((k) => k === 'rejected_events_summary')).toHaveLength(1);
  });

  it('M4: a global cap on salons waiting for activation; cleanup removes stale ones', async () => {
    const pending = (await ctx.vendor.list('pending_activation')).length;
    const capped = await startApp(testConfig({ MAX_PENDING_SALONS: String(pending + 1) }));
    try {
      const reg = (name: string) =>
        capped
          .http()
          .post('/v1/salons/register')
          .send({ salon: { name, timezone: 'Asia/Riyadh', currency: 'SAR' }, owner: { name: 'O', username: `own${Date.now().toString(36)}${name.length}`, password: 'staff-password-1' } });
      expect((await reg('صالون أ')).status).toBe(201);
      const second = await reg('صالون بب');
      expect(second.status).toBe(503);
      expect(second.body.error.code).toBe('REGISTRATION_PAUSED');
      const removed = await capped.vendor.cleanupPending(1, false, Date.now() + 2 * 86_400_000);
      expect(removed.length).toBeGreaterThanOrEqual(1);
      expect(await capped.vendor.list('pending_activation')).toEqual([]);
      expect((await reg('صالون ججج')).status).toBe(201);
      await capped.vendor.cleanupPending(1, false, Date.now() + 2 * 86_400_000);
    } finally {
      await capped.close();
    }
  });

  // ─── L1 ────────────────────────────────────────────────────────────────────────────
  it('L1: device times are clamped to the booking lifetime; such samples are excluded', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const id = (await book(ctx, await newCustomer(ctx, s), { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    clock(ctx).set(at(5));
    expect((await push(ctx, b, [event(ctx, b, 'service_started', id, {}, at(-45))]))[0]!.result).toBe('applied');
    expect((await status(s.dbName, id)).actual_start).toEqual(new Date(at(0))); // not before the booking existed
    clock(ctx).set(at(40));
    expect((await push(ctx, b, [event(ctx, b, 'service_finished', id, {}, at(-10))]))[0]!.result).toBe('applied');
    expect((await status(s.dbName, id)).actual_end).toEqual(new Date(at(0)));
    const [smp] = await salonQuery(ctx, s.dbName, 'SELECT excluded, exclusion_reason FROM duration_samples WHERE booking_id = $1', [id]);
    expect(smp).toEqual({ excluded: true, exclusion_reason: 'clamped_time' });
  });

  // ─── L3 / L8 ───────────────────────────────────────────────────────────────────────
  it('L3/L8: https-only social links; upper bounds on prices and durations', async () => {
    const s = await setupQueueSalon(ctx);
    const m = auth(s.manager.accessToken);
    for (const url of ['http://instagram.com/x', 'javascript:alert(1)', 'https://user:pw@x.com/']) {
      const r = await ctx.http().put('/v1/manager/profile').set(m).send({ socialLinks: [{ platform: 'x', url }] });
      expect(r.status).toBe(400);
    }
    expect((await ctx.http().put('/v1/manager/profile').set(m).send({ socialLinks: [{ platform: 'x', url: 'https://x.com/s' }] })).status).toBe(200);
    expect((await ctx.http().post('/v1/manager/services').set(m).send({ name: 'غالية', durationMinutes: 30, price: 100_000_001 })).status).toBe(400);
    expect((await ctx.http().post('/v1/manager/services').set(m).send({ name: 'طويلة', durationMinutes: 481, price: 100 })).status).toBe(400);
    expect((await ctx.http().post('/v1/manager/services').set(m).send({ name: 'عادية', durationMinutes: 480, price: 100_000_000 })).status).toBe(201);
  });

  // ─── L5 ────────────────────────────────────────────────────────────────────────────
  it('L5: the owner is protected; concurrent demotions never leave the salon without an active manager', async () => {
    const s = await setupQueueSalon(ctx);
    const mk = async (username: string) => {
      const r = await ctx.http().post('/v1/manager/staff').set(auth(s.manager.accessToken)).send({ name: 'M', username, password: 'staff-password-1', role: 'manager' });
      return { id: r.body.id as string, token: (await staffLogin(ctx, s.code, username)).body.accessToken as string };
    };
    const m2 = await mk(`mgr${Date.now().toString(36)}a`);
    const m3 = await mk(`mgr${Date.now().toString(36)}b`);
    const [owner] = await salonQuery(ctx, s.dbName, 'SELECT is_owner FROM staff WHERE id = $1', [s.manager.id]);
    expect(owner.is_owner).toBe(true);
    const demoteOwner = await ctx.http().put(`/v1/manager/staff/${s.manager.id}`).set(auth(m2.token)).send({ role: 'barber' });
    expect(demoteOwner.body.error.code).toBe('OWNER_PROTECTED');
    expect((await ctx.http().put(`/v1/manager/staff/${s.manager.id}`).set(auth(m2.token)).send({ active: false })).body.error.code).toBe('OWNER_PROTECTED');

    // Without an owner (legacy data) and the owner gone: m2 and m3 demote each other at the same time.
    await salonQuery(ctx, s.dbName, 'UPDATE staff SET is_owner = false, active = false WHERE id = $1', [s.manager.id]);
    const res = await Promise.all([
      ctx.http().put(`/v1/manager/staff/${m3.id}`).set(auth(m2.token)).send({ role: 'barber' }),
      ctx.http().put(`/v1/manager/staff/${m2.id}`).set(auth(m3.token)).send({ role: 'barber' }),
    ]);
    expect(res.map((r) => r.status).sort()).not.toEqual([200, 200]);
    const [n] = await salonQuery(ctx, s.dbName, "SELECT count(*)::int AS n FROM staff WHERE role = 'manager' AND active");
    expect(n.n).toBe(1);
  });
});

/** M1 needs real rate limits and a short account-wide delay. */
describe('review fixes — login throttling (M1)', () => {
  let ctx: TestContext;
  beforeAll(async () => {
    ctx = await startApp(
      testConfig({
        RATE_LIMITS_ENABLED: 'true',
        BACKOFF_FREE_ATTEMPTS: '100',
        BACKOFF_IP_FREE_ATTEMPTS: '100',
        BACKOFF_ACCOUNT_FREE_ATTEMPTS: '2',
        BACKOFF_ACCOUNT_BASE_MS: '400',
        BACKOFF_ACCOUNT_MAX_DELAY_MS: '400',
      }),
    );
  });
  afterAll(() => closeQueueApp(ctx));

  it('rate-limit keys are normalised (spellings of one phone share one budget); a slow account-wide delay, never a lockout', async () => {
    const s = await setupQueueSalon(ctx);
    const digits = '05' + String(Math.floor(Math.random() * 1e8)).padStart(8, '0');
    await registerCustomer(ctx, s.code, digits);
    const arabic = digits.replace(/\d/g, (d) => '٠١٢٣٤٥٦٧٨٩'[Number(d)]!);
    const spellings = [digits, `${digits.slice(0, 3)} ${digits.slice(3)}`, arabic, `${digits.slice(0, 3)}-${digits.slice(3)}`];
    const login = (phone: string, ip: string, password = 'wrong-password') =>
      ctx.http().post('/v1/auth/customer/login').set('X-Forwarded-For', ip).send({ salonCode: ` ${s.code.toLowerCase()} `, phone, password });
    const codes: number[] = [];
    for (let i = 0; i < 11; i++) codes.push((await login(spellings[i % spellings.length]!, `10.9.${i}.1`)).status);
    expect(codes.slice(0, 10).every((c) => c === 401)).toBe(true);
    expect(codes[10]).toBe(429); // the per-account budget (10 / 15 min) is shared by every spelling

    // Account-wide delay: failures from many IPs slow the answer down but the right password still works.
    const phone2 = randomPhone();
    await registerCustomer(ctx, s.code, phone2);
    for (let i = 0; i < 3; i++) await login(phone2, `10.8.${i}.1`);
    const t0 = Date.now();
    const ok = await login(phone2, '10.7.0.1', 'cust-pass1');
    expect(ok.status).toBe(200);
    expect(Date.now() - t0).toBeGreaterThanOrEqual(380);
  });

  it('M4: device sync pushes have a per-account budget', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    let last = 0;
    for (let i = 0; i < 61; i++) last = (await ctx.http().post('/v1/sync/events').set(auth(b.token)).set('X-Forwarded-For', `10.6.${i}.1`).send({ events: [] })).status;
    expect(last).toBe(429);
  });

});

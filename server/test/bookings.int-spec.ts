import { randomUUID } from 'node:crypto';
import { salonQuery, startApp, TestContext } from './helpers';
import {
  at,
  auth,
  book,
  clock,
  event,
  heartbeat,
  isoAt,
  MIN,
  newCustomer,
  notifications,
  push,
  runScheduler,
  settle,
  setupQueueSalon,
  T0,
  closeQueueApp,
  dropCreatedSalons,
} from './queue-helpers';

/** Customer booking flows (api.md "الزبون", design §3 and §5). */
describe('bookings', () => {
  let ctx: TestContext;
  beforeAll(async () => {
    ctx = await startApp();
  });
  afterAll(() => closeQueueApp(ctx));
  beforeEach(() => clock(ctx).set(T0));
  afterEach(() => dropCreatedSalons(ctx));

  const quote = (token: string, body: Record<string, unknown>) =>
    ctx.http().post('/v1/bookings/quote').set(auth(token)).set('Idempotency-Key', randomUUID()).send(body);

  it('end to end: quote → book → call → start → finish → payment (with notifications)', async () => {
    const s = await setupQueueSalon(ctx);
    const [b] = s.barbers;
    const c = await newCustomer(ctx, s);

    const today = await ctx.http().get('/v1/customer/today').set(auth(c.token));
    expect(today.status).toBe(200);
    expect(today.body.services.map((x: { id: string }) => x.id)).toContain(s.services.haircut);
    expect(today.body.barbers).toEqual([
      expect.objectContaining({ id: b!.id, dayState: 'not_connected_yet', nextAvailableStart: isoAt(0), queueLength: 0, accepting: true }),
    ]);

    const q = await quote(c.token, { serviceIds: [s.services.haircut], barberId: b!.id, kind: 'queue' });
    expect(q.status).toBe(200);
    expect(q.body).toMatchObject({ barberId: b!.id, start: isoAt(0), end: isoAt(30), durationMin: 30, price: 5000, outcome: 'accept' });

    const r = await book(ctx, c, { serviceIds: [s.services.haircut], barberId: b!.id, kind: 'queue' });
    expect(r.status).toBe(201);
    expect(r.body).toMatchObject({ status: 'waiting', barberId: b!.id, customerId: c.id, originalEta: isoAt(0), lastShownEta: isoAt(0), eta: isoAt(0), priceCents: 5000, walkIn: false, source: 'app', queuePosition: 0 });
    expect(r.body.serviceIds).toEqual([s.services.haircut]);
    const id = r.body.id as string;

    let cur = await ctx.http().get('/v1/bookings/current').set(auth(c.token));
    expect(cur.status).toBe(200);
    expect(cur.body).toMatchObject({ eta: isoAt(0), originalEta: isoAt(0), status: 'waiting', progress: { done: 0, ahead: 0 }, live: false });

    await heartbeat(ctx, b!);
    cur = await ctx.http().get('/v1/bookings/current').set(auth(c.token));
    expect(cur.body.live).toBe(true);

    await runScheduler(ctx, s);
    const [called] = await salonQuery(ctx, s.dbName, 'SELECT status, called_at FROM bookings WHERE id = $1', [id]);
    expect(called.status).toBe('called');

    clock(ctx).set(at(2));
    await heartbeat(ctx, b!);
    let out = await push(ctx, b!, [event(ctx, b!, 'service_started', id)]);
    expect(out[0]!.result).toBe('applied');

    clock(ctx).set(at(35));
    await heartbeat(ctx, b!);
    out = await push(ctx, b!, [event(ctx, b!, 'service_finished', id)]);
    expect(out[0]!.result).toBe('applied');
    const [done] = await salonQuery(ctx, s.dbName, 'SELECT status, actual_start, actual_end FROM bookings WHERE id = $1', [id]);
    expect(done.status).toBe('done');
    expect(done.actual_end.getTime() - done.actual_start.getTime()).toBe(33 * MIN);
    const [sample] = await salonQuery(ctx, s.dbName, 'SELECT duration_seconds, excluded FROM duration_samples WHERE booking_id = $1', [id]);
    expect(sample).toEqual({ duration_seconds: 33 * 60, excluded: false });

    const pays = await ctx.http().get('/v1/staff/payments').set(auth(b!.token));
    expect(pays.body).toEqual([expect.objectContaining({ bookingId: id, amountCents: 5000, status: 'awaiting_confirmation' })]);

    const confirm = event(ctx, b!, 'payment_confirmed', id, { amount: 5000 });
    expect((await push(ctx, b!, [confirm]))[0]!.result).toBe('applied');
    expect((await push(ctx, b!, [confirm]))[0]!.result).toBe('duplicate');
    // A second confirmation is idempotent: accepted, nothing changes.
    expect(await push(ctx, b!, [event(ctx, b!, 'payment_confirmed', id, { amount: 1 })])).toEqual([
      expect.objectContaining({ result: 'applied', reason: 'ALREADY_CONFIRMED' }),
    ]);
    const [pay] = await salonQuery(ctx, s.dbName, 'SELECT status, amount_minor FROM payments WHERE booking_id = $1', [id]);
    expect(pay).toEqual({ status: 'confirmed', amount_minor: '5000' });

    const hist = await ctx.http().get('/v1/customer/history').set(auth(c.token));
    expect(hist.body).toEqual([expect.objectContaining({ id, status: 'done', payment: { status: 'confirmed', amountCents: 5000 } })]);
    expect((await ctx.http().get('/v1/bookings/current').set(auth(c.token))).status).toBe(404);

    await settle(ctx);
    const sent = await notifications(ctx, s, 'recipient_id = $1', [c.id]);
    expect(sent.map((n) => n.type)).toEqual(['booking_confirmed', 'called']);
    expect(sent[0].body).toContain('تم حجز دورك عند');
    expect(sent[1].high_priority).toBe(true);
    expect(sent.every((n) => n.status === 'no_device')).toBe(true);
    // Every change is logged with its reason in the append-only trail.
    const evs = await salonQuery(ctx, s.dbName, 'SELECT type FROM booking_events WHERE booking_id = $1 ORDER BY received_at, occurred_at', [id]);
    expect(evs.map((e) => e.type)).toEqual(expect.arrayContaining(['created', 'called', 'service_started', 'service_finished', 'payment_confirmed']));
  });

  it('ق4/ق19: a new booking never delays anyone; it uses a gap only with the safety margin', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const [x, y, z, w] = [await newCustomer(ctx, s), await newCustomer(ctx, s), await newCustomer(ctx, s), await newCustomer(ctx, s)];
    const rx = await book(ctx, x, { serviceIds: [s.services.haircut], barberId: b.id, kind: 'requested', requestedAt: isoAt(60) });
    expect(rx.body.eta).toBe(isoAt(60));
    const ry = await book(ctx, y, { serviceIds: [s.services.haircut], barberId: b.id, kind: 'queue' });
    expect(ry.body.eta).toBe(isoAt(0));
    // 60 min does not fit the 30 min gap (10:30–11:00) → after the 11:00 booking.
    const rz = await book(ctx, z, { serviceIds: [s.services.long], barberId: b.id, kind: 'queue' });
    expect(rz.body.eta).toBe(isoAt(90));
    // 15 min fits: 30 ≥ 15 + max(10, 25%).
    const rw = await book(ctx, w, { serviceIds: [s.services.beard], barberId: b.id, kind: 'queue' });
    expect(rw.body.eta).toBe(isoAt(30));
    const rows = await salonQuery(ctx, s.dbName, 'SELECT id, projected_start, queue_position FROM bookings ORDER BY queue_position');
    expect(rows.map((r) => r.id)).toEqual([ry.body.id, rw.body.id, rx.body.id, rz.body.id]);
    expect(rows.map((r) => r.projected_start.getTime())).toEqual([at(0), at(30), at(60), at(90)]);
    // Nobody moved: no eta_changed events.
    expect(await salonQuery(ctx, s.dbName, "SELECT 1 FROM booking_events WHERE type = 'eta_changed'")).toHaveLength(0);
  });

  it('ق13: an exact hour is booked; otherwise one held offer, which expires', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const [c1, c2, c3, c4] = [await newCustomer(ctx, s), await newCustomer(ctx, s), await newCustomer(ctx, s), await newCustomer(ctx, s)];
    const svc = [s.services.haircut];
    const q1 = await quote(c1.token, { serviceIds: svc, barberId: b.id, kind: 'requested', requestedAt: isoAt(90) });
    expect(q1.body).toMatchObject({ outcome: 'accept', start: isoAt(90) });
    expect(q1.body.offerId).toBeUndefined();
    expect((await book(ctx, c1, { serviceIds: svc, barberId: b.id, kind: 'requested', requestedAt: isoAt(90) })).body.eta).toBe(isoAt(90));

    // 11:40 is taken (11:30–12:00) → the nearest time only, held for 2 minutes.
    const q2 = await quote(c2.token, { serviceIds: svc, barberId: b.id, kind: 'requested', requestedAt: isoAt(100) });
    expect(q2.body).toMatchObject({ outcome: 'offer', start: isoAt(120), offerExpiresAt: isoAt(2) });
    const [held] = await salonQuery(ctx, s.dbName, 'SELECT status FROM bookings WHERE id = $1', [q2.body.offerId]);
    expect(held.status).toBe('offered');
    // Direct booking of an unavailable hour is refused with the nearest time (the held offer is respected).
    const direct = await book(ctx, c3, { serviceIds: svc, barberId: b.id, kind: 'requested', requestedAt: isoAt(120) });
    expect(direct.status).toBe(409);
    expect(direct.body.error.code).toBe('SLOT_UNAVAILABLE');
    expect(direct.body.error.details.nearest).toBe(isoAt(150));

    const acc = await book(ctx, c2, { offerId: q2.body.offerId });
    expect(acc.status).toBe(201);
    expect(acc.body).toMatchObject({ id: q2.body.offerId, status: 'waiting', eta: isoAt(120), kind: 'requested' });

    // Offer that expires before acceptance.
    const q3 = await quote(c3.token, { serviceIds: svc, barberId: b.id, kind: 'requested', requestedAt: isoAt(100) });
    expect(q3.body.outcome).toBe('offer');
    clock(ctx).set(at(3));
    const late = await book(ctx, c3, { offerId: q3.body.offerId });
    expect(late.status).toBe(410);
    expect(late.body.error.code).toBe('OFFER_EXPIRED');
    await runScheduler(ctx, s);
    const [exp] = await salonQuery(ctx, s.dbName, 'SELECT status FROM bookings WHERE id = $1', [q3.body.offerId]);
    expect(exp.status).toBe('expired');

    // Rejecting an offer releases it.
    const q4 = await quote(c4.token, { serviceIds: svc, barberId: b.id, kind: 'requested', requestedAt: isoAt(100) });
    expect((await ctx.http().delete(`/v1/offers/${q4.body.offerId}`).set(auth(c4.token))).status).toBe(204);
    const [rej] = await salonQuery(ctx, s.dbName, 'SELECT status FROM bookings WHERE id = $1', [q4.body.offerId]);
    expect(rej.status).toBe('expired');
    expect((await ctx.http().delete(`/v1/offers/${q4.body.offerId}`).set(auth(c4.token))).status).toBe(204);
  });

  it('enforces the booking window, the working hours and the account approval', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const c = await newCustomer(ctx, s);
    const svc = [s.services.haircut];
    clock(ctx).set(at(-150)); // 07:30 — booking opens at 08:00
    const early = await book(ctx, c, { serviceIds: svc, barberId: b.id, kind: 'queue' });
    expect(early.status).toBe(409);
    expect(early.body.error.code).toBe('BOOKING_CLOSED');
    clock(ctx).set(at(-100)); // 08:20
    const ok = await book(ctx, c, { serviceIds: svc, barberId: b.id, kind: 'queue' });
    expect(ok.status).toBe(201);
    expect(ok.body.eta).toBe(isoAt(-60)); // 09:00 opening
    const c2 = await newCustomer(ctx, s);
    const outside = await book(ctx, c2, { serviceIds: svc, barberId: b.id, kind: 'requested', requestedAt: isoAt(14 * 60) });
    expect(outside.body.error.code).toBe('OUTSIDE_WORKING_HOURS');
    const badSvc = await book(ctx, c2, { serviceIds: [randomUUID()], kind: 'queue' });
    expect(badSvc.body.error.code).toBe('SERVICE_UNAVAILABLE');

    await ctx.http().put('/v1/manager/settings').set(auth(s.manager.accessToken)).send({ requireAccountApproval: true });
    const pending = await newCustomer(ctx, s);
    const r = await book(ctx, pending, { serviceIds: svc, kind: 'queue' });
    expect(r.status).toBe(403);
    expect(r.body.error.code).toBe('ACCOUNT_PENDING');
    expect((await quote(pending.token, { serviceIds: svc, kind: 'queue' })).status).toBe(403);
  });

  it('max active bookings per customer (setting, default 1) and idempotent creation', async () => {
    const s = await setupQueueSalon(ctx, { barbers: 2 });
    const c = await newCustomer(ctx, s);
    const svc = [s.services.haircut];
    const key = randomUUID();
    const first = await book(ctx, c, { serviceIds: svc, kind: 'queue' }, key);
    expect(first.status).toBe(201);
    const again = await book(ctx, c, { serviceIds: svc, kind: 'queue' }, key);
    expect(again.status).toBe(201);
    expect(again.body.id).toBe(first.body.id);
    expect(await salonQuery(ctx, s.dbName, 'SELECT 1 FROM bookings')).toHaveLength(1);

    const second = await book(ctx, c, { serviceIds: svc, kind: 'queue' });
    expect(second.status).toBe(409);
    expect(second.body.error.code).toBe('MAX_ACTIVE_BOOKINGS');
    await ctx.http().put('/v1/manager/settings').set(auth(s.manager.accessToken)).send({ maxActiveBookingsPerCustomer: 2 });
    expect((await book(ctx, c, { serviceIds: svc, kind: 'queue' })).status).toBe(201);
    expect((await book(ctx, c, { serviceIds: svc, kind: 'queue' })).body.error.code).toBe('MAX_ACTIVE_BOOKINGS');
    const cancel = await ctx.http().post(`/v1/bookings/${first.body.id}/cancel`).set(auth(c.token)).set('Idempotency-Key', randomUUID());
    expect(cancel.status).toBe(200);
    expect((await book(ctx, c, { serviceIds: svc, kind: 'queue' })).status).toBe(201);
  });

  it('auto-assign picks the barber who can start soonest and then fixes him', async () => {
    const s = await setupQueueSalon(ctx, { barbers: 2 });
    const [b1, b2] = s.barbers;
    const svc = [s.services.haircut];
    const r1 = await book(ctx, await newCustomer(ctx, s), { serviceIds: svc, kind: 'queue' });
    const r2 = await book(ctx, await newCustomer(ctx, s), { serviceIds: svc, kind: 'queue' });
    expect(new Set([r1.body.barberId, r2.body.barberId])).toEqual(new Set([b1!.id, b2!.id]));
    expect(r1.body.eta).toBe(isoAt(0));
    expect(r2.body.eta).toBe(isoAt(0));
    const r3 = await book(ctx, await newCustomer(ctx, s), { serviceIds: svc, kind: 'queue' });
    expect(r3.body.eta).toBe(isoAt(30));
  });

  it('parallel bookings for one barber never overlap or share a position (§5.13)', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const customers = await Promise.all(Array.from({ length: 10 }, () => newCustomer(ctx, s)));
    const res = await Promise.all(customers.map((c) => book(ctx, c, { serviceIds: [s.services.haircut], barberId: b.id, kind: 'queue' })));
    expect(res.map((r) => r.status)).toEqual(Array(10).fill(201));
    const rows = await salonQuery(ctx, s.dbName, "SELECT queue_position, projected_start, projected_end FROM bookings WHERE status = 'waiting' ORDER BY queue_position");
    expect(rows.map((r) => r.queue_position)).toEqual([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    for (let i = 1; i < rows.length; i++) expect(rows[i].projected_start.getTime()).toBeGreaterThanOrEqual(rows[i - 1].projected_end.getTime());
    expect(rows[9].projected_start.getTime()).toBe(at(270));

    // Two barbers, auto-assign, in parallel.
    const s2 = await setupQueueSalon(ctx, { barbers: 2 });
    const cs = await Promise.all(Array.from({ length: 8 }, () => newCustomer(ctx, s2)));
    const res2 = await Promise.all(cs.map((c) => book(ctx, c, { serviceIds: [s2.services.haircut], kind: 'queue' })));
    expect(res2.every((r) => r.status === 201)).toBe(true);
    for (const bb of s2.barbers) {
      const q = await salonQuery(ctx, s2.dbName, 'SELECT queue_position, projected_start, projected_end FROM bookings WHERE staff_id = $1 ORDER BY queue_position', [bb.id]);
      expect(q.map((r) => r.queue_position)).toEqual(q.map((_, i) => i));
      for (let i = 1; i < q.length; i++) expect(q[i].projected_start.getTime()).toBeGreaterThanOrEqual(q[i - 1].projected_end.getTime());
    }
  });

  it('change-time (§5.12): moves atomically, or keeps the booking and holds the nearest time', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const [c, other] = [await newCustomer(ctx, s), await newCustomer(ctx, s)];
    const svc = [s.services.haircut];
    const mine = (await book(ctx, c, { serviceIds: svc, barberId: b.id, kind: 'queue' })).body;
    await book(ctx, other, { serviceIds: svc, barberId: b.id, kind: 'requested', requestedAt: isoAt(180) });
    const change = (body: Record<string, unknown>) =>
      ctx.http().post(`/v1/bookings/${mine.id}/change-time`).set(auth(c.token)).set('Idempotency-Key', randomUUID()).send(body);

    const moved = await change({ kind: 'requested', requestedAt: isoAt(120) });
    expect(moved.status).toBe(200);
    expect(moved.body).toMatchObject({ id: mine.id, kind: 'requested', eta: isoAt(120), lastShownEta: isoAt(120), originalEta: isoAt(0) });

    const busy = await change({ kind: 'requested', requestedAt: isoAt(190) });
    expect(busy.status).toBe(409);
    expect(busy.body.error.code).toBe('SLOT_UNAVAILABLE');
    const offer = busy.body.error.details.offer;
    expect(offer).toMatchObject({ outcome: 'offer', start: isoAt(210) });
    const [still] = await salonQuery(ctx, s.dbName, 'SELECT status, projected_start FROM bookings WHERE id = $1', [mine.id]);
    expect(still.status).toBe('waiting');
    expect(still.projected_start.getTime()).toBe(at(120));

    const acc = await book(ctx, c, { offerId: offer.offerId });
    expect(acc.status).toBe(201);
    expect(acc.body).toMatchObject({ id: mine.id, eta: isoAt(210), originalEta: isoAt(0) });
    const active = await salonQuery(ctx, s.dbName, "SELECT id FROM bookings WHERE customer_id = $1 AND status IN ('waiting','called','offered')", [c.id]);
    expect(active).toEqual([{ id: mine.id }]);
    const events = await salonQuery(ctx, s.dbName, "SELECT reason FROM booking_events WHERE booking_id = $1 AND type = 'time_changed'", [mine.id]);
    expect(events).toHaveLength(2);
  });

  it('cancel (ق29): before start only; the ones behind move earlier with a recorded reason', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const [c1, c2] = [await newCustomer(ctx, s), await newCustomer(ctx, s)];
    const svc = [s.services.haircut];
    const r1 = (await book(ctx, c1, { serviceIds: svc, barberId: b.id, kind: 'queue' })).body;
    const r2 = (await book(ctx, c2, { serviceIds: svc, barberId: b.id, kind: 'queue' })).body;
    expect(r2.eta).toBe(isoAt(30));
    const res = await ctx.http().post(`/v1/bookings/${r1.id}/cancel`).set(auth(c1.token)).set('Idempotency-Key', randomUUID());
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('cancelled');
    const [ev] = await salonQuery(ctx, s.dbName, "SELECT reason, payload FROM booking_events WHERE booking_id = $1 AND type = 'eta_changed'", [r2.id]);
    expect(ev.reason).toBe('cancelled_ahead');
    expect(ev.payload.after).toBe(isoAt(0));
    const cur = await ctx.http().get('/v1/bookings/current').set(auth(c2.token));
    expect(cur.body.lastChangeReason).toBe('ألغى زبون قبلك حجزه');
    expect(cur.body.eta).toBe(isoAt(0));

    await heartbeat(ctx, b);
    await push(ctx, b, [event(ctx, b, 'service_started', r2.id)]);
    const late = await ctx.http().post(`/v1/bookings/${r2.id}/cancel`).set(auth(c2.token));
    expect(late.status).toBe(409);
    expect(late.body.error.code).toBe('BOOKING_STARTED');
    const audit = await salonQuery(ctx, s.dbName, "SELECT target_id FROM audit_log WHERE action = 'booking.cancelled'");
    expect(audit).toEqual([{ target_id: r1.id }]);
  });

  it('seen updates the ق5 reference; devices can be registered', async () => {
    const s = await setupQueueSalon(ctx);
    const c = await newCustomer(ctx, s);
    const r = (await book(ctx, c, { serviceIds: [s.services.haircut], kind: 'queue' })).body;
    const seen = await ctx.http().post(`/v1/bookings/${r.id}/seen`).set(auth(c.token)).send({ eta: isoAt(5) });
    expect(seen.status).toBe(204);
    const [row] = await salonQuery(ctx, s.dbName, 'SELECT last_shown_expected_start AS v, original_expected_start AS o FROM bookings WHERE id = $1', [r.id]);
    expect(row.v.getTime()).toBe(at(5));
    expect(row.o.getTime()).toBe(at(0));
    const dev = await ctx.http().post('/v1/devices').set(auth(c.token)).send({ fcmToken: 'token-abcdefghijkl', notificationsAllowed: true, hasPlayServices: true });
    expect(dev.status).toBe(200);
    const [d] = await salonQuery(ctx, s.dbName, 'SELECT owner_kind, owner_id FROM devices');
    expect(d).toEqual({ owner_kind: 'customer', owner_id: c.id });
  });
});

import { randomUUID } from 'node:crypto';
import { salonQuery, startApp, TestContext } from './helpers';
import {
  at,
  auth,
  book,
  clock,
  event,
  fake,
  heartbeat,
  isoAt,
  liveUntil,
  newCustomer,
  notifications,
  push,
  registerDevice,
  runScheduler,
  setupQueueSalon,
  staffToday,
  T0,
} from './queue-helpers';

/** Background loop: day states (§4), ق3, calling (§5.5), ق5/ق23, ق27, ق32. */
describe('scheduler', () => {
  let ctx: TestContext;
  beforeAll(async () => {
    ctx = await startApp();
  });
  afterAll(() => ctx.close());
  beforeEach(() => clock(ctx).set(T0));

  const svc = (s: { services: { haircut: string } }) => [s.services.haircut];

  it('ق3: ≥ 2 h of known work → remote bookings continue (appended) for 2 h after the drop; auto-assign skips him', async () => {
    const s = await setupQueueSalon(ctx, { barbers: 2 });
    const [b1, b2] = s.barbers;
    for (let i = 0; i < 5; i++) await book(ctx, await newCustomer(ctx, s), { serviceIds: svc(s), barberId: b1!.id, kind: 'queue' });
    await heartbeat(ctx, b1!); // knows 150 min of work
    await heartbeat(ctx, b2!);
    clock(ctx).set(at(2)); // b1 silent for 120 s → disconnected
    await heartbeat(ctx, b2!);
    await runScheduler(ctx, s);
    const [day] = await salonQuery(ctx, s.dbName, 'SELECT state, offline_since FROM barber_days WHERE staff_id = $1', [b1!.id]);
    expect(day.state).toBe('disconnected');
    expect(day.offline_since.getTime()).toBe(T0);

    const appended = await book(ctx, await newCustomer(ctx, s), { serviceIds: svc(s), barberId: b1!.id, kind: 'queue' });
    expect(appended.status).toBe(201);
    expect(appended.body.eta).toBe(isoAt(150));
    expect(appended.body.queuePosition).toBe(5);
    const auto = await book(ctx, await newCustomer(ctx, s), { serviceIds: svc(s), kind: 'queue' });
    expect(auto.body.barberId).toBe(b2!.id);

    const cust = await newCustomer(ctx, s);
    const cur = await ctx.http().get('/v1/customer/today').set(auth(cust.token));
    expect(cur.body.barbers.find((x: { id: string }) => x.id === b1!.id)).toMatchObject({ dayState: 'disconnected', accepting: true });

    clock(ctx).set(at(121));
    const stopped = await book(ctx, cust, { serviceIds: svc(s), barberId: b1!.id, kind: 'queue' });
    expect(stopped.status).toBe(409);
    expect(stopped.body.error.code).toBe('BARBER_UNAVAILABLE');
    // Back online → bookings resume automatically.
    const hb = await heartbeat(ctx, b1!);
    expect(hb).toMatchObject({ state: 'connected', reconnected: true });
    expect((await book(ctx, cust, { serviceIds: svc(s), barberId: b1!.id, kind: 'queue' })).status).toBe(201);
  });

  it('ق3: < 2 h of known work → remote bookings stop immediately when he drops', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    await book(ctx, await newCustomer(ctx, s), { serviceIds: svc(s), barberId: b.id, kind: 'queue' });
    await heartbeat(ctx, b);
    clock(ctx).set(at(1.6));
    const r = await book(ctx, await newCustomer(ctx, s), { serviceIds: svc(s), barberId: b.id, kind: 'queue' });
    expect(r.status).toBe(409);
    expect(r.body.error.code).toBe('BARBER_UNAVAILABLE');
    // ق26: before the first connection of the day booking is open normally.
    const s2 = await setupQueueSalon(ctx);
    expect((await book(ctx, await newCustomer(ctx, s2), { serviceIds: svc(s2), kind: 'queue' })).status).toBe(201);
  });

  it('calls within the barber lead time only, one at a time (§5.5)', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const r1 = (await book(ctx, await newCustomer(ctx, s), { serviceIds: svc(s), kind: 'requested', requestedAt: isoAt(60) })).body.id;
    const r2 = (await book(ctx, await newCustomer(ctx, s), { serviceIds: svc(s), kind: 'requested', requestedAt: isoAt(90) })).body.id;
    await heartbeat(ctx, b);
    await runScheduler(ctx, s);
    const status = async () => (await salonQuery(ctx, s.dbName, 'SELECT id, status FROM bookings ORDER BY queue_position')).map((x) => x.status);
    expect(await status()).toEqual(['waiting', 'waiting']);
    await liveUntil(ctx, b, 40);
    await runScheduler(ctx, s);
    expect(await status()).toEqual(['called', 'waiting']);
    await liveUntil(ctx, b, 75);
    await runScheduler(ctx, s);
    // The called one has not arrived: never a second call (no automatic release either).
    expect(await status()).toEqual(['called', 'waiting']);
    expect(r1).not.toBe(r2);
  });

  it('ق5 later + ق27: an overrun beyond 30 min notifies once; the barber is reminded at 100%', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const [c0, c1, c2] = [await newCustomer(ctx, s), await newCustomer(ctx, s), await newCustomer(ctx, s)];
    const r0 = (await book(ctx, c0, { serviceIds: svc(s), kind: 'queue' })).body.id;
    await book(ctx, c1, { serviceIds: svc(s), kind: 'queue' });
    const r2 = (await book(ctx, c2, { serviceIds: svc(s), kind: 'queue' })).body;
    expect(r2.eta).toBe(isoAt(60));
    await registerDevice(ctx, c2.token, 'fcm-token-customer-two');
    await registerDevice(ctx, b.token, 'fcm-token-barber-device');
    await heartbeat(ctx, b);
    await push(ctx, b, [event(ctx, b, 'service_started', r0)]);
    const etaNotices = () => notifications(ctx, s, "type = 'eta_changed' AND recipient_id = $1", [c2.id]);

    await liveUntil(ctx, b, 30);
    await runScheduler(ctx, s);
    expect(await notifications(ctx, s, "type = 'overrun'")).toHaveLength(1);

    await liveUntil(ctx, b, 50);
    await runScheduler(ctx, s); // c2 at 80: +20 → nothing yet
    expect(await etaNotices()).toHaveLength(0);

    await liveUntil(ctx, b, 65);
    await runScheduler(ctx, s); // c2 at 95: +35 → mandatory notice
    const n = await etaNotices();
    expect(n).toHaveLength(1);
    expect(n[0].body).toContain('تأخر');
    expect(n[0].body).toContain('استغرقت الخدمة الحالية وقتًا أطول من المتوقع');
    expect(n[0].status).toBe('sent');
    expect(fake(ctx).sent.some((m) => m.token === 'fcm-token-customer-two' && m.data.type === 'eta_changed' && m.data.bookingId === r2.id)).toBe(true);
    const [row] = await salonQuery(ctx, s.dbName, 'SELECT last_shown_expected_start AS v FROM bookings WHERE id = $1', [r2.id]);
    expect(row.v.getTime()).toBe(at(95));

    await liveUntil(ctx, b, 66);
    await runScheduler(ctx, s);
    expect(await etaNotices()).toHaveLength(1);
    expect(await notifications(ctx, s, "type = 'overrun'")).toHaveLength(1);
    expect(fake(ctx).sent.filter((m) => m.token === 'fcm-token-barber-device' && m.data.type === 'overrun')).toHaveLength(1);
  });

  it('ق5/ق23 earlier: moving forward by more than 30 min is notified too', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const [c0, c1, c2] = [await newCustomer(ctx, s), await newCustomer(ctx, s), await newCustomer(ctx, s)];
    const r0 = (await book(ctx, c0, { serviceIds: svc(s), kind: 'queue' })).body.id;
    const r1 = (await book(ctx, c1, { serviceIds: [s.services.long], kind: 'queue' })).body.id;
    const r2 = (await book(ctx, c2, { serviceIds: svc(s), kind: 'queue' })).body;
    expect(r2.eta).toBe(isoAt(90));
    await heartbeat(ctx, b);
    await push(ctx, b, [event(ctx, b, 'service_started', r0)]);
    await ctx.http().post(`/v1/bookings/${r1}/cancel`).set(auth(c1.token)).set('Idempotency-Key', randomUUID());
    await runScheduler(ctx, s);
    const n = await notifications(ctx, s, "type = 'eta_changed' AND recipient_id = $1", [c2.id]);
    expect(n).toHaveLength(1);
    expect(n[0].body).toContain('تقدّم');
    expect(n[0].body).toContain('ألغى زبون قبلك حجزه');
  });

  it('§4: no ETA notices while the barber is offline; one reconciled notice when he is back', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const [c0, c1, c2] = [await newCustomer(ctx, s), await newCustomer(ctx, s), await newCustomer(ctx, s)];
    const r0 = (await book(ctx, c0, { serviceIds: svc(s), kind: 'queue' })).body.id;
    const r1 = (await book(ctx, c1, { serviceIds: [s.services.long], kind: 'queue' })).body.id;
    await book(ctx, c2, { serviceIds: svc(s), kind: 'queue' });
    await heartbeat(ctx, b);
    await push(ctx, b, [event(ctx, b, 'service_started', r0)]);
    clock(ctx).set(at(3)); // offline since T0
    await ctx.http().post(`/v1/bookings/${r1}/cancel`).set(auth(c1.token));
    await runScheduler(ctx, s);
    const etaNotices = () => notifications(ctx, s, "type = 'eta_changed' AND recipient_id = $1", [c2.id]);
    expect(await etaNotices()).toHaveLength(0);
    const cur = await ctx.http().get('/v1/bookings/current').set(auth(c2.token));
    expect(cur.body).toMatchObject({ live: false, dayState: 'disconnected', lastUpdateAt: isoAt(0) });

    clock(ctx).set(at(4));
    await heartbeat(ctx, b);
    await runScheduler(ctx, s);
    const n = await etaNotices();
    expect(n).toHaveLength(1);
    expect(n[0].body).toContain('وصلنا تحديث من الصالون بعد انقطاع');
    await runScheduler(ctx, s);
    expect(await etaNotices()).toHaveLength(1);
    const [day] = await salonQuery(ctx, s.dbName, 'SELECT state, offline_since FROM barber_days WHERE staff_id = $1', [b.id]);
    expect(day).toEqual({ state: 'connected', offline_since: null });
  });

  it('ق32: the manager is alerted once when a barber has not connected at his shift start', async () => {
    const s = await setupQueueSalon(ctx);
    clock(ctx).set(at(-75)); // 08:45 — before the shift
    await runScheduler(ctx, s);
    expect(await notifications(ctx, s, "type = 'barber_not_connected'")).toHaveLength(0);
    clock(ctx).set(at(-59)); // 09:01
    await runScheduler(ctx, s);
    await runScheduler(ctx, s);
    const n = await notifications(ctx, s, "type = 'barber_not_connected'");
    expect(n).toHaveLength(1);
    expect(n[0].recipient_id).toBe(s.manager.id);
  });

  it('ق24: impact preview and today flag bookings pushed past closing until the barber decides', async () => {
    const s = await setupQueueSalon(ctx, { closes: '11:00' });
    const b = s.barbers[0]!;
    const r1 = (await book(ctx, await newCustomer(ctx, s), { serviceIds: svc(s), kind: 'queue' })).body.id;
    const r2 = (await book(ctx, await newCustomer(ctx, s), { serviceIds: svc(s), kind: 'queue' })).body.id;
    const full = await book(ctx, await newCustomer(ctx, s), { serviceIds: svc(s), kind: 'queue' });
    expect(full.body.error.code).toBe('NO_SLOT');
    await heartbeat(ctx, b);
    await push(ctx, b, [event(ctx, b, 'service_started', r1)]);
    const imp = await ctx.http().post('/v1/staff/impact').set(auth(b.token)).send({ bookingId: r1, serviceIds: [s.services.long] });
    expect(imp.body.pastClosing).toEqual([expect.objectContaining({ bookingId: r2, end: isoAt(90), newlyPastClosing: true })]);
    await push(ctx, b, [event(ctx, b, 'services_changed', r1, { serviceIds: [s.services.long] })]);
    expect((await staffToday(ctx, b)).closingWarnings).toEqual([r2]);
    await push(ctx, b, [event(ctx, b, 'closing_decision', r2, { decision: 'serve_late' })]);
    expect((await staffToday(ctx, b)).closingWarnings).toEqual([]);
  });
});

import { randomUUID } from 'node:crypto';
import sharp from 'sharp';
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
  MIN,
  newCustomer,
  notifications,
  push,
  runScheduler,
  settle,
  setupQueueSalon,
  T0,
} from './queue-helpers';

/** Manager queues, manual transfer (ق25), the base-duration alert (§5.10), and client-contract shapes. */
describe('manager queues & transfer', () => {
  let ctx: TestContext;
  beforeAll(async () => {
    ctx = await startApp();
  });
  afterAll(() => closeQueueApp(ctx));
  beforeEach(() => clock(ctx).set(T0));
  afterEach(() => dropCreatedSalons(ctx));

  const transfer = (token: string, id: string, toBarberId: string, key: string = randomUUID()) =>
    ctx.http().post(`/v1/manager/bookings/${id}/transfer`).set(auth(token)).set('Idempotency-Key', key).send({ toBarberId });

  it('GET /manager/queues lists every barber today with state and queue details', async () => {
    const s = await setupQueueSalon(ctx, { barbers: 2 });
    const [b1, b2] = s.barbers;
    const c = await newCustomer(ctx, s);
    const r = await book(ctx, c, { serviceIds: [s.services.haircut, s.services.beard], barberId: b1!.id, kind: 'queue' });
    expect(r.status).toBe(201);
    await heartbeat(ctx, b2!);
    const w = await ctx.http().post('/v1/staff/walk-ins').set(auth(b2!.token)).set('Idempotency-Key', randomUUID()).send({ name: 'حاضر', phone: '0551234567', serviceIds: [s.services.haircut] });
    expect(w.status).toBe(201);

    const q = await ctx.http().get('/v1/manager/queues').set(auth(s.manager.accessToken));
    expect(q.status).toBe(200);
    expect(q.body.serverTime).toBe(isoAt(0));
    expect(typeof q.body.seq).toBe('number');
    const byId = new Map(q.body.barbers.map((x: { id: string }) => [x.id, x]));
    expect(byId.size).toBe(2);
    const one = byId.get(b1!.id) as any;
    expect(one).toMatchObject({ name: 'Barber', role: 'barber', accepting: true, day: { workDate: '2026-03-05', state: 'not_connected_yet' } });
    expect(one.queue).toEqual([
      expect.objectContaining({
        id: r.body.id,
        customerName: 'زبون',
        customerPhone: c.phone,
        status: 'waiting',
        eta: isoAt(0),
        etaEnd: isoAt(45),
        kind: 'queue',
        walkIn: false,
        serviceIds: [s.services.haircut, s.services.beard],
        services: [expect.objectContaining({ name: 'قص' }), expect.objectContaining({ name: 'لحية' })],
      }),
    ]);
    const two = byId.get(b2!.id) as any;
    expect(two.day.state).toBe('connected');
    expect(two.queue).toEqual([expect.objectContaining({ walkIn: true, customerName: 'حاضر', customerPhone: '0551234567' })]);

    // Managers only.
    expect((await ctx.http().get('/v1/manager/queues').set(auth(b1!.token))).status).toBe(403);
    expect((await ctx.http().get('/v1/manager/queues').set(auth(c.token))).status).toBe(403);
    expect((await ctx.http().get('/v1/manager/queues')).status).toBe(401);
  });

  it('transfers a waiting booking under ق4: removed at source, inserted at target, recorded, notified, idempotent', async () => {
    const s = await setupQueueSalon(ctx, { barbers: 2 });
    const [b1, b2] = s.barbers;
    const c1 = await newCustomer(ctx, s);
    const c2 = await newCustomer(ctx, s);
    const c3 = await newCustomer(ctx, s);
    const c4 = await newCustomer(ctx, s);
    const first = await book(ctx, c1, { serviceIds: [s.services.long], barberId: b1!.id, kind: 'queue' }); // 10:00–11:00
    const moved = await book(ctx, c2, { serviceIds: [s.services.haircut], barberId: b1!.id, kind: 'queue' }); // 11:00–11:30
    const behind = await book(ctx, c4, { serviceIds: [s.services.haircut], barberId: b1!.id, kind: 'queue' }); // 11:30–12:00
    const other = await book(ctx, c3, { serviceIds: [s.services.haircut], barberId: b2!.id, kind: 'queue' }); // b2 10:00–10:30
    for (const r of [first, moved, behind, other]) expect(r.status).toBe(201);
    expect(moved.body.eta).toBe(isoAt(60));
    const id = moved.body.id as string;

    const key = randomUUID();
    const r = await transfer(s.manager.accessToken, id, b2!.id, key);
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ id, barberId: b2!.id, status: 'waiting', eta: isoAt(30), originalEta: isoAt(60), lastShownEta: isoAt(30), queuePosition: 1 });

    // Replay returns the first result and changes nothing more.
    const again = await transfer(s.manager.accessToken, id, b2!.id, key);
    expect(again.status).toBe(200);
    expect(again.body).toEqual(r.body);

    const [row] = await salonQuery(ctx, s.dbName, 'SELECT staff_id, status, last_change_reason FROM bookings WHERE id = $1', [id]);
    expect(row).toEqual({ staff_id: b2!.id, status: 'waiting', last_change_reason: 'transferred' });
    // The customer behind moved up at the source (ETA history carries the reason).
    const [b] = await salonQuery(ctx, s.dbName, 'SELECT projected_start, queue_position, last_change_reason FROM bookings WHERE id = $1', [behind.body.id]);
    expect(b.projected_start.getTime()).toBe(at(60));
    expect(b.queue_position).toBe(1);
    expect(b.last_change_reason).toBe('transferred_ahead');
    // Nobody at the target was delayed (ق4).
    const [o] = await salonQuery(ctx, s.dbName, 'SELECT projected_start FROM bookings WHERE id = $1', [other.body.id]);
    expect(o.projected_start.getTime()).toBe(at(0));

    const events = await salonQuery(ctx, s.dbName, "SELECT type, reason, actor_kind, actor_id, payload FROM booking_events WHERE booking_id = $1 AND type = 'transferred'", [id]);
    expect(events).toEqual([
      expect.objectContaining({
        reason: 'transferred',
        actor_kind: 'staff',
        actor_id: s.manager.id,
        payload: expect.objectContaining({ fromBarberId: b1!.id, toBarberId: b2!.id, previousStatus: 'waiting', before: isoAt(60), after: isoAt(30) }),
      }),
    ]);
    const audit = await salonQuery(ctx, s.dbName, "SELECT actor_id, target_id FROM audit_log WHERE action = 'booking.transferred'");
    expect(audit).toEqual([{ actor_id: s.manager.id, target_id: id }]);
    const changes = await salonQuery(ctx, s.dbName, "SELECT type, staff_id FROM changes WHERE entity_id = $1 AND type IN ('booking_removed', 'booking_created') ORDER BY seq", [id]);
    expect(changes).toEqual([
      { type: 'booking_created', staff_id: b1!.id },
      { type: 'booking_removed', staff_id: b1!.id },
      { type: 'booking_created', staff_id: b2!.id },
    ]);

    await settle(ctx);
    const sent = await notifications(ctx, s, "recipient_id = $1 AND type = 'transferred'", [c2.id]);
    expect(sent).toHaveLength(1);
    expect(sent[0].body).toMatch(/^نُقل حجزك إلى Barber — الوقت المتوقع /);
    expect(sent[0].data).toMatchObject({ type: 'transferred', bookingId: id, eta: isoAt(30), barberId: b2!.id });

    // The customer's own screen follows the new barber.
    const cur = await ctx.http().get('/v1/bookings/current').set(auth(c2.token));
    expect(cur.body).toMatchObject({ eta: isoAt(30), barber: { id: b2!.id }, lastChangeReasonCode: 'transferred' });

    // Both barbers' sync feeds see it.
    const feed1 = await ctx.http().get('/v1/sync?since=0').set(auth(b1!.token));
    expect(feed1.body.changes.some((ch: { type: string; bookingId?: string }) => ch.type === 'booking_removed' && ch.bookingId === id)).toBe(true);
    const feed2 = await ctx.http().get('/v1/sync?since=0').set(auth(b2!.token));
    expect(feed2.body.changes.some((ch: { type: string; bookingId?: string }) => ch.type === 'booking_created' && ch.bookingId === id)).toBe(true);
  });

  it('a called booking becomes waiting at the new barber', async () => {
    const s = await setupQueueSalon(ctx, { barbers: 2 });
    const [b1, b2] = s.barbers;
    const c = await newCustomer(ctx, s);
    const r = await book(ctx, c, { serviceIds: [s.services.haircut], barberId: b1!.id, kind: 'queue' });
    await heartbeat(ctx, b1!);
    await runScheduler(ctx, s);
    const [called] = await salonQuery(ctx, s.dbName, 'SELECT status FROM bookings WHERE id = $1', [r.body.id]);
    expect(called.status).toBe('called');

    const t = await transfer(s.manager.accessToken, r.body.id, b2!.id);
    expect(t.status).toBe(200);
    expect(t.body).toMatchObject({ status: 'waiting', barberId: b2!.id, calledAt: null });
    const ev = await salonQuery(ctx, s.dbName, "SELECT payload FROM booking_events WHERE booking_id = $1 AND type = 'transferred'", [r.body.id]);
    expect(ev[0].payload.previousStatus).toBe('called');
  });

  it('refuses a transfer that does not fit (409 with the nearest alternatives) and other invalid transfers', async () => {
    const s = await setupQueueSalon(ctx, { barbers: 3 });
    const [b1, b2, b3] = s.barbers;
    // b2 closes at 10:20 today: a 30-minute haircut no longer fits.
    await salonQuery(ctx, s.dbName, "UPDATE work_schedules SET closes_at = '10:20' WHERE staff_id = $1", [b2!.id]);
    const c = await newCustomer(ctx, s);
    const r = await book(ctx, c, { serviceIds: [s.services.haircut], barberId: b1!.id, kind: 'queue' });
    const id = r.body.id as string;

    const no = await transfer(s.manager.accessToken, id, b2!.id);
    expect(no.status).toBe(409);
    expect(no.body.error.code).toBe('TRANSFER_NO_SLOT');
    expect(no.body.error.details).toEqual({
      nearest: { barberId: b3!.id, barberName: 'Barber', start: isoAt(0), end: isoAt(30) },
      alternatives: [{ barberId: b3!.id, barberName: 'Barber', start: isoAt(0), end: isoAt(30) }],
    });
    const [row] = await salonQuery(ctx, s.dbName, 'SELECT staff_id, status FROM bookings WHERE id = $1', [id]);
    expect(row).toEqual({ staff_id: b1!.id, status: 'waiting' });

    const same = await transfer(s.manager.accessToken, id, b1!.id);
    expect(same.status).toBe(409);
    expect(same.body.error.code).toBe('TRANSFER_SAME_BARBER');
    const unknown = await transfer(s.manager.accessToken, id, randomUUID());
    expect(unknown.status).toBe(404);
    expect(unknown.body.error.code).toBe('BARBER_NOT_FOUND');
    expect((await transfer(s.manager.accessToken, randomUUID(), b3!.id)).status).toBe(404);

    // Absent target.
    await ctx.http().post('/v1/manager/absences').set(auth(s.manager.accessToken)).send({ staffId: b3!.id, workDate: '2026-03-05' });
    const absent = await transfer(s.manager.accessToken, id, b3!.id);
    expect(absent.body.error.code).toBe('BARBER_ABSENT');

    // Started service: no transfer.
    clock(ctx).set(at(1));
    await heartbeat(ctx, b1!);
    expect((await push(ctx, b1!, [event(ctx, b1!, 'service_started', id)]))[0]!.result).toBe('applied');
    const started = await transfer(s.manager.accessToken, id, s.barbers[1]!.id);
    expect(started.status).toBe(409);
    expect(started.body.error.code).toBe('BOOKING_STARTED');
  });

  it('only managers transfer; never across salons', async () => {
    const A = await setupQueueSalon(ctx, { barbers: 2 });
    const B = await setupQueueSalon(ctx, { barbers: 1 });
    const c = await newCustomer(ctx, A);
    const r = await book(ctx, c, { serviceIds: [A.services.haircut], barberId: A.barbers[0]!.id, kind: 'queue' });
    const id = r.body.id as string;

    expect((await transfer(A.barbers[0]!.token, id, A.barbers[1]!.id)).status).toBe(403);
    expect((await transfer(c.token, id, A.barbers[1]!.id)).status).toBe(403);
    expect((await ctx.http().post(`/v1/manager/bookings/${id}/transfer`).send({ toBarberId: A.barbers[1]!.id })).status).toBe(401);

    // B's manager cannot see or move A's booking, not even with crafted headers.
    const foreign = await ctx
      .http()
      .post(`/v1/manager/bookings/${id}/transfer`)
      .set(auth(B.manager.accessToken))
      .set('X-Salon-Code', A.code)
      .set('Idempotency-Key', randomUUID())
      .send({ toBarberId: B.barbers[0]!.id });
    expect(foreign.status).toBe(404);
    // A's manager cannot move a booking to B's barber.
    const toForeign = await transfer(A.manager.accessToken, id, B.barbers[0]!.id);
    expect(toForeign.status).toBe(404);
    expect(toForeign.body.error.code).toBe('BARBER_NOT_FOUND');
    const qB = await ctx.http().get('/v1/manager/queues').set(auth(B.manager.accessToken));
    expect(qB.body.barbers.map((x: { id: string }) => x.id)).toEqual([B.barbers[0]!.id]);

    const [row] = await salonQuery(ctx, A.dbName, 'SELECT staff_id, status FROM bookings WHERE id = $1', [id]);
    expect(row).toEqual({ staff_id: A.barbers[0]!.id, status: 'waiting' });
  });

  it('alerts the managers once when a barber\'s samples keep rejecting the base duration (§5.10)', async () => {
    const s = await setupQueueSalon(ctx, { barbers: 1 });
    const [b] = s.barbers;
    const alerts = () => notifications(ctx, s, "type = 'base_duration_suspect'");
    // Haircut base = 30 min; 100-minute services are outside 30%–300% → rejected as samples.
    for (let i = 0; i < 6; i++) {
      await heartbeat(ctx, b!);
      const w = await ctx.http().post('/v1/staff/walk-ins').set(auth(b!.token)).set('Idempotency-Key', randomUUID()).send({ name: `حاضر ${i}`, phone: `05500000${10 + i}`, serviceIds: [s.services.haircut] });
      expect(w.status).toBe(201);
      expect((await push(ctx, b!, [event(ctx, b!, 'service_started', w.body.id)]))[0]!.result).toBe('applied');
      clock(ctx).set(clock(ctx).now() + 100 * MIN);
      await heartbeat(ctx, b!);
      expect((await push(ctx, b!, [event(ctx, b!, 'service_finished', w.body.id)]))[0]!.result).toBe('applied');
      if (i === 3) expect(await alerts()).toHaveLength(0); // fewer than 5 samples: no verdict yet
    }
    const got = await alerts();
    expect(got).toHaveLength(1); // once per service set per day
    expect(got[0]).toMatchObject({ recipient_kind: 'staff', recipient_id: s.manager.id });
    expect(got[0].body).toContain('«قص»');
    expect(got[0].body).toContain('المدة الأساسية');
    expect(got[0].data).toMatchObject({ type: 'base_duration_suspect', barberId: b!.id, serviceSetKey: s.services.haircut, baseDurationMin: '30' });
  });

  it('GET /manager/profile carries photo and logo media URLs', async () => {
    const s = await setupQueueSalon(ctx, { barbers: 0 });
    const png = await sharp({ create: { width: 8, height: 8, channels: 3, background: { r: 1, g: 2, b: 3 } } }).png().toBuffer();
    const up = await ctx.http().post('/v1/manager/photos').set(auth(s.manager.accessToken)).attach('file', png, 'a.png');
    expect(up.status).toBe(201);
    expect(up.body.url).toBe(`/v1/media/${s.code}/${up.body.path.split('/')[1]}`);
    const logo = await ctx.http().post('/v1/manager/profile/logo').set(auth(s.manager.accessToken)).attach('file', png, 'l.png');
    expect(logo.status).toBe(201);
    expect(logo.body.logo).toMatch(new RegExp(`^/v1/media/${s.code}/`));

    const p = await ctx.http().get('/v1/manager/profile').set(auth(s.manager.accessToken));
    expect(p.status).toBe(200);
    expect(p.body).toMatchObject({ code: s.code, logo: logo.body.logo, photos: [{ id: up.body.id, url: up.body.url, position: 1 }] });
    // Same URLs as the public profile, and they are served.
    const pub = await ctx.http().get(`/v1/salons/${s.code}`);
    expect(pub.body.logo).toBe(p.body.logo);
    expect(pub.body.photos).toEqual(p.body.photos);
    expect((await ctx.http().get(p.body.photos[0].url)).status).toBe(200);
  });

  it('GET /bookings/current is 200 with booking null when there is no active booking', async () => {
    const s = await setupQueueSalon(ctx, { barbers: 1 });
    const c = await newCustomer(ctx, s);
    const cur = await ctx.http().get('/v1/bookings/current').set(auth(c.token));
    expect(cur.status).toBe(200);
    expect(cur.body).toEqual({ booking: null, serverTime: isoAt(0) });
  });

  it('a pending customer cannot book: 403 ACCOUNT_PENDING (quote, book, change-time)', async () => {
    const s = await setupQueueSalon(ctx, { barbers: 1 });
    await ctx.http().put('/v1/manager/settings').set(auth(s.manager.accessToken)).send({ requireAccountApproval: true });
    const c = await newCustomer(ctx, s);
    const body = { serviceIds: [s.services.haircut], kind: 'queue' };
    const r = await book(ctx, c, body);
    expect(r.status).toBe(403);
    expect(r.body).toEqual({ error: { code: 'ACCOUNT_PENDING', message: expect.any(String) } });
    const q = await ctx.http().post('/v1/bookings/quote').set(auth(c.token)).send(body);
    expect(q.body.error.code).toBe('ACCOUNT_PENDING');
    const ch = await ctx.http().post(`/v1/bookings/${randomUUID()}/change-time`).set(auth(c.token)).send({ kind: 'queue' });
    expect(ch.body.error.code).toBe('ACCOUNT_PENDING');
    const today = await ctx.http().get('/v1/customer/today').set(auth(c.token));
    expect(today.body.accountStatus).toBe('pending');
  });
});

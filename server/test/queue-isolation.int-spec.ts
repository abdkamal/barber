import { randomUUID } from 'node:crypto';
import type { AddressInfo } from 'node:net';
import { salonQuery, startApp, TestContext } from './helpers';
import { auth, book, clock, Customer, event, heartbeat, isoAt, newCustomer, push, QueueSalon, runScheduler, setupQueueSalon, staffToday, T0, closeQueueApp } from './queue-helpers';

/**
 * Cross-tenant isolation for every milestone-4b endpoint (design §7): the salon comes only from
 * the verified token; ids of another salon behave as if they did not exist.
 */
describe('queue endpoints — tenant isolation and roles', () => {
  let ctx: TestContext;
  let A: QueueSalon;
  let B: QueueSalon;
  let bookingA: string;
  let customerA: Customer;
  let customerB: Customer;

  beforeAll(async () => {
    ctx = await startApp();
    clock(ctx).set(T0);
    A = await setupQueueSalon(ctx);
    B = await setupQueueSalon(ctx);
    customerA = await newCustomer(ctx, A);
    customerB = await newCustomer(ctx, B);
    bookingA = (await book(ctx, customerA, { serviceIds: [A.services.haircut], kind: 'queue' })).body.id;
  });
  afterAll(() => closeQueueApp(ctx));

  const crafted = (r: ReturnType<ReturnType<TestContext['http']>['get']>) => r.set('X-Salon-Id', A.id).set('X-Salon-Code', A.code);

  it('customer endpoints never reach another salon', async () => {
    const h = auth(customerB.token);
    // A's services / barbers do not exist for B's customer.
    const q = await crafted(ctx.http().post('/v1/bookings/quote').set(h)).send({ serviceIds: [A.services.haircut], kind: 'queue' });
    expect(q.body.error.code).toBe('SERVICE_UNAVAILABLE');
    const q2 = await crafted(ctx.http().post('/v1/bookings').set(h)).send({ serviceIds: [B.services.haircut], barberId: A.barbers[0]!.id, kind: 'queue' });
    expect(q2.body.error.code).toBe('BARBER_NOT_FOUND');
    for (const [method, path, body] of [
      ['post', `/v1/bookings/${bookingA}/cancel`, {}],
      ['post', `/v1/bookings/${bookingA}/change-time`, { kind: 'queue' }],
      ['post', `/v1/bookings/${bookingA}/seen`, { eta: isoAt(0) }],
      ['delete', `/v1/offers/${bookingA}`, undefined],
    ] as const) {
      const r = await crafted((ctx.http() as any)[method](path).set(h).set('Idempotency-Key', randomUUID())).send(body);
      expect(r.status).toBe(404);
    }
    const cur = await crafted(ctx.http().get('/v1/bookings/current').set(h));
    expect(cur.status).toBe(200);
    expect(cur.body.booking).toBeNull();
    const offerByA = await crafted(ctx.http().post('/v1/bookings').set(h)).send({ offerId: bookingA });
    expect(offerByA.status).toBe(404);
    const hist = await crafted(ctx.http().get('/v1/customer/history').set(h));
    expect(hist.body).toEqual([]);
    const today = await crafted(ctx.http().get('/v1/customer/today').set(h));
    expect(today.body.barbers.map((x: { id: string }) => x.id)).toEqual([B.barbers[0]!.id]);
    const [row] = await salonQuery(ctx, A.dbName, 'SELECT status, last_shown_expected_start FROM bookings WHERE id = $1', [bookingA]);
    expect(row.status).toBe('waiting');
    expect(row.last_shown_expected_start.getTime()).toBe(T0);
  });

  it('staff endpoints and sync never reach another salon', async () => {
    const bB = B.barbers[0]!;
    const h = auth(bB.token);
    const out = await push(ctx, bB, [event(ctx, bB, 'service_started', bookingA), event(ctx, bB, 'payment_confirmed', bookingA)]);
    expect(out.map((o) => o.reason)).toEqual(['BOOKING_NOT_FOUND', 'BOOKING_NOT_FOUND']);
    expect((await salonQuery(ctx, A.dbName, 'SELECT status FROM bookings WHERE id = $1', [bookingA]))[0].status).toBe('waiting');
    expect(await salonQuery(ctx, A.dbName, 'SELECT 1 FROM device_events')).toHaveLength(0);
    const imp = await crafted(ctx.http().post('/v1/staff/impact').set(h)).send({ bookingId: bookingA, serviceIds: [B.services.haircut] });
    expect(imp.status).toBe(404);
    const w = await crafted(ctx.http().post('/v1/staff/walk-ins').set(h)).send({ name: 'x', phone: '0555111222', serviceIds: [A.services.haircut] });
    expect(w.body.error.code).toBe('SERVICE_UNAVAILABLE');
    const today = await staffToday(ctx, bB);
    expect(today.queue).toEqual([]);
    const pull = await crafted(ctx.http().get('/v1/sync?since=0').set(h));
    expect(JSON.stringify(pull.body)).not.toContain(bookingA);
    const pay = await crafted(ctx.http().get('/v1/staff/payments').set(h));
    expect(pay.body).toEqual([]);
    // Heartbeats only touch the token's salon.
    await heartbeat(ctx, bB);
    expect(await salonQuery(ctx, A.dbName, 'SELECT 1 FROM barber_days WHERE last_heartbeat_at IS NOT NULL')).toHaveLength(0);
    // The manager of B sees nothing of A either.
    const mgr = await ctx.http().get('/v1/sync?since=0').set(auth(B.manager.accessToken));
    expect(JSON.stringify(mgr.body)).not.toContain(bookingA);
  });

  it('the scheduler keeps each salon to itself', async () => {
    await heartbeat(ctx, A.barbers[0]!);
    await runScheduler(ctx, B);
    expect((await salonQuery(ctx, A.dbName, 'SELECT status FROM bookings WHERE id = $1', [bookingA]))[0].status).toBe('waiting');
    await runScheduler(ctx, A);
    expect((await salonQuery(ctx, A.dbName, 'SELECT status FROM bookings WHERE id = $1', [bookingA]))[0].status).toBe('called');
    expect(await salonQuery(ctx, B.dbName, 'SELECT 1 FROM notifications WHERE booking_id IS NOT NULL')).toHaveLength(0);
  });

  it('WebSocket rooms are per salon', async () => {
    const server = ctx.app.getHttpServer();
    await new Promise<void>((res) => server.listen(0, '127.0.0.1', () => res()));
    const port = (server.address() as AddressInfo).port;
    const { WebSocket } = await import('ws');
    const open = (token: string) =>
      new Promise<{ ws: InstanceType<typeof WebSocket>; msgs: Array<{ type: string }> }>((res, rej) => {
        const ws = new WebSocket(`ws://127.0.0.1:${port}/v1/staff/stream`, { headers: { Authorization: `Bearer ${token}`, 'X-Salon-Id': A.id } });
        const msgs: Array<{ type: string }> = [];
        ws.on('message', (d) => msgs.push(JSON.parse(String(d))));
        ws.on('open', () => res({ ws, msgs }));
        ws.on('error', rej);
      });
    const mgrB = await open(B.manager.accessToken);
    const barberA = await open(A.barbers[0]!.token);
    await book(ctx, await newCustomer(ctx, A), { serviceIds: [A.services.haircut], kind: 'queue' });
    for (let i = 0; i < 50 && !barberA.msgs.some((m) => m.type === 'changes'); i++) await new Promise((r) => setTimeout(r, 20));
    expect(barberA.msgs.some((m) => m.type === 'changes')).toBe(true);
    expect(mgrB.msgs.filter((m) => m.type === 'changes')).toHaveLength(0);
    mgrB.ws.close();
    barberA.ws.close();
  });

  it('roles: customers cannot use staff endpoints and vice versa', async () => {
    const c = auth(customerA.token);
    for (const [m, p] of [
      ['get', '/v1/staff/today'],
      ['post', '/v1/sync/events'],
      ['get', '/v1/sync?since=0'],
      ['post', '/v1/heartbeat'],
      ['post', '/v1/staff/walk-ins'],
      ['post', '/v1/staff/impact'],
      ['get', '/v1/staff/payments'],
    ] as const) {
      expect((await (ctx.http() as any)[m](p).set(c).send({})).status).toBe(403);
    }
    const s = auth(A.barbers[0]!.token);
    for (const [m, p] of [
      ['get', '/v1/customer/today'],
      ['post', '/v1/bookings'],
      ['post', '/v1/bookings/quote'],
      ['get', '/v1/bookings/current'],
      ['get', '/v1/customer/history'],
    ] as const) {
      expect((await (ctx.http() as any)[m](p).set(s).send({})).status).toBe(403);
    }
    expect((await ctx.http().get('/v1/staff/today')).status).toBe(401);
  });
});

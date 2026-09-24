import { randomUUID } from 'node:crypto';
import { salonQuery, startApp, STAFF_PW, TestContext, uniq } from './helpers';
import { auth, book, clock, closeQueueApp, dropCreatedSalons, heartbeat, newCustomer, setupQueueSalon, T0 } from './queue-helpers';

/**
 * Phase 11 — first trial feedback (round 2): diagnosable failures (request id, validation details),
 * salon registration with every country/timezone and currency the staff app offers, and the manager
 * who also cuts hair as a transfer target (ق25) consistently with who is bookable.
 */
describe('trial feedback round 2', () => {
  let ctx: TestContext;
  beforeAll(async () => {
    ctx = await startApp();
  });
  afterAll(() => closeQueueApp(ctx));
  beforeEach(() => clock(ctx).set(T0));
  afterEach(() => dropCreatedSalons(ctx));

  describe('request id', () => {
    it('every response carries X-Request-Id; a well-formed incoming id is kept, a bad one replaced', async () => {
      const ok = await ctx.http().get('/v1/health');
      expect(ok.headers['x-request-id']).toMatch(/^[0-9a-f-]{36}$/);
      const nf = await ctx.http().get('/v1/salons/NOPE-11');
      expect(nf.status).toBe(404);
      expect(nf.headers['x-request-id']).toMatch(/^[0-9a-f-]{36}$/);
      const kept = await ctx.http().get('/v1/health').set('X-Request-Id', 'caddy-req-12345678');
      expect(kept.headers['x-request-id']).toBe('caddy-req-12345678');
      const bad = await ctx.http().get('/v1/health').set('X-Request-Id', 'x y');
      expect(bad.headers['x-request-id']).not.toBe('x y');
      // Malformed JSON (body parser) still gets an id.
      const malformed = await ctx.http().post('/v1/salons/register').set('Content-Type', 'application/json').send('{"salon":');
      expect(malformed.status).toBe(400);
      expect(malformed.headers['x-request-id']).toBeDefined();
    });
  });

  describe('salon registration as the staff app sends it (ق37, ق41)', () => {
    // apps/staff/lib/features/signup/signup_screen.dart: signupRegions × SaloniCurrency.supported.
    const REGIONS = [
      'Asia/Riyadh', 'Asia/Dubai', 'Asia/Kuwait', 'Asia/Qatar', 'Asia/Bahrain', 'Asia/Muscat',
      'Asia/Amman', 'Asia/Hebron', 'Asia/Gaza', 'Asia/Jerusalem', 'Africa/Cairo',
    ];
    const CURRENCIES = ['SAR', 'AED', 'KWD', 'QAR', 'BHD', 'OMR', 'JOD', 'EGP', 'ILS'];
    // Every region at least once and every currency at least once (ILS with all Palestinian zones).
    const CASES: Array<[string, string]> = [
      ['Asia/Riyadh', 'SAR'], ['Asia/Dubai', 'AED'], ['Asia/Kuwait', 'KWD'], ['Asia/Qatar', 'QAR'],
      ['Asia/Bahrain', 'BHD'], ['Asia/Muscat', 'OMR'], ['Asia/Amman', 'JOD'], ['Africa/Cairo', 'EGP'],
      ['Asia/Hebron', 'ILS'], ['Asia/Gaza', 'ILS'], ['Asia/Jerusalem', 'ILS'], ['Asia/Hebron', 'JOD'],
    ];

    it('covers every offered region and currency', () => {
      expect(new Set(CASES.map((c) => c[0]))).toEqual(new Set(REGIONS));
      expect(new Set(CASES.map((c) => c[1]))).toEqual(new Set(CURRENCIES));
    });

    it.each(CASES)('registers with %s / %s and completes the signup follow-ups', async (timezone, currency) => {
      const username = uniq('own').toLowerCase();
      const res = await ctx
        .http()
        .post('/v1/salons/register')
        .send({
          salon: { name: `صالون ${timezone.split('/')[1]}`, timezone, currency, phone: '٠٥٩٩١٢٣٤٥٦', address: 'الخليل', about: 'نبذة' },
          owner: { name: 'المالك', username, password: STAFF_PW },
        });
      expect(res.status).toBe(201);
      expect(res.body.salon).toMatchObject({ timezone, currency, status: 'pending_activation' });
      const token = res.body.session.accessToken as string;
      // The app then saves the salon hours (default schedule per day) and the services.
      for (let weekday = 0; weekday < 7; weekday++) {
        const s = await ctx.http().put('/v1/manager/schedules').set(auth(token)).send({ staffId: null, weekday, opensAt: '10:00', closesAt: '23:00' });
        expect(s.status).toBe(200);
      }
      const svc = await ctx.http().post('/v1/manager/services').set(auth(token)).send({ name: 'قص', durationMinutes: 30, price: 3500 });
      expect(svc.status).toBe(201);
      // Free international WhatsApp (ق41) — the country code of the salon or any other.
      const wa = await ctx.http().put('/v1/manager/profile').set(auth(token)).send({ whatsapp: '00970599123456' });
      expect(wa.status).toBe(200);
      expect(wa.body.whatsapp).toBe('+970599123456');
      const settings = await ctx.http().get('/v1/manager/settings').set(auth(token));
      expect(settings.status).toBe(200);
      await ctx.vendor.activate(res.body.salon.code); // not left pending (M4 cap)
    });

    it('validation errors name the field and the problem (no values)', async () => {
      const base = { salon: { name: 'صالون الوادي', timezone: 'Asia/Hebron', currency: 'ILS' }, owner: { name: 'م', username: uniq('ok'), password: STAFF_PW } };
      const bad = await ctx.http().post('/v1/salons/register').send({ ...base, owner: { ...base.owner, username: '_owner' } });
      expect(bad.status).toBe(400);
      expect(bad.body.error).toEqual({ code: 'VALIDATION_FAILED', message: expect.any(String), details: [{ path: 'owner.username', code: 'invalid_username' }] });
      const tz = await ctx.http().post('/v1/salons/register').send({ ...base, salon: { ...base.salon, timezone: 'Asia/Hebronx' } });
      expect(tz.body.error.details).toEqual([{ path: 'salon.timezone', code: 'invalid_timezone' }]);
      const short = await ctx.http().post('/v1/salons/register').send({ ...base, salon: { ...base.salon, name: 'x' } });
      expect(short.body.error.details).toEqual([{ path: 'salon.name', code: 'too_small' }]);
      expect(JSON.stringify(short.body)).not.toContain(STAFF_PW);
    });
  });

  describe('a manager who also cuts hair (ق25)', () => {
    const transfer = (token: string, id: string, toBarberId: string) =>
      ctx.http().post(`/v1/manager/bookings/${id}/transfer`).set(auth(token)).set('Idempotency-Key', randomUUID()).send({ toBarberId });

    it('without an own schedule: not bookable, not listed, not a transfer target (the salon default is for barbers)', async () => {
      const s = await setupQueueSalon(ctx, { barbers: 1 });
      await salonQuery(ctx, s.dbName, "INSERT INTO work_schedules (staff_id, weekday, opens_at, closes_at) SELECT NULL, d, '09:00', '23:00' FROM generate_series(0, 6) d");
      const c = await newCustomer(ctx, s);
      const r = await book(ctx, c, { serviceIds: [s.services.haircut], barberId: s.barbers[0]!.id, kind: 'queue' });
      expect(r.status).toBe(201);

      const q = await ctx.http().get('/v1/manager/queues').set(auth(s.manager.accessToken));
      expect(q.body.barbers.map((b: { id: string }) => b.id)).toEqual([s.barbers[0]!.id]);
      const today = await ctx.http().get('/v1/customer/today').set(auth(c.token));
      expect(today.body.barbers.map((b: { id: string }) => b.id)).not.toContain(s.manager.id);
      const t = await transfer(s.manager.accessToken, r.body.id, s.manager.id);
      expect(t.status).toBe(409);
      expect(t.body.error.code).toBe('BARBER_NOT_WORKING');
    });

    it('with an own schedule: bookable, listed in the queues, a valid transfer target both ways, can add walk-ins', async () => {
      const s = await setupQueueSalon(ctx, { barbers: 1 });
      const [b1] = s.barbers;
      // What «اعمل بدوام الصالون» does: the manager's own rows via the normal endpoint.
      for (let weekday = 0; weekday < 7; weekday++) {
        const put = await ctx.http().put('/v1/manager/schedules').set(auth(s.manager.accessToken)).send({ staffId: s.manager.id, weekday, opensAt: '09:00', closesAt: '23:00' });
        expect(put.status).toBe(200);
      }
      const c = await newCustomer(ctx, s);
      const today = await ctx.http().get('/v1/customer/today').set(auth(c.token));
      expect(today.body.barbers.map((b: { id: string }) => b.id)).toEqual(expect.arrayContaining([b1!.id, s.manager.id]));

      const r = await book(ctx, c, { serviceIds: [s.services.haircut], barberId: b1!.id, kind: 'queue' });
      expect(r.status).toBe(201);
      const q = await ctx.http().get('/v1/manager/queues').set(auth(s.manager.accessToken));
      const mine = q.body.barbers.find((b: { id: string }) => b.id === s.manager.id);
      expect(mine).toMatchObject({ role: 'manager', accepting: true, day: { workDate: '2026-03-05' } });

      const toManager = await transfer(s.manager.accessToken, r.body.id, s.manager.id);
      expect(toManager.status).toBe(200);
      expect(toManager.body).toMatchObject({ id: r.body.id, barberId: s.manager.id, status: 'waiting' });
      const mineToday = await ctx.http().get('/v1/staff/today').set(auth(s.manager.accessToken));
      expect(mineToday.body.day).not.toBeNull();
      expect(mineToday.body.queue.map((b: { id: string }) => b.id)).toContain(r.body.id);

      await heartbeat(ctx, b1!);
      const back = await transfer(s.manager.accessToken, r.body.id, b1!.id);
      expect(back.status).toBe(200);
      expect(back.body.barberId).toBe(b1!.id);

      const walkIn = await ctx.http().post('/v1/staff/walk-ins').set(auth(s.manager.accessToken)).set('Idempotency-Key', randomUUID()).send({ name: 'حاضر', phone: '0599000111', serviceIds: [s.services.haircut] });
      expect(walkIn.status).toBe(201);
      expect(walkIn.body.barberId).toBe(s.manager.id);
    });
  });
});

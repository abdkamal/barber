import sharp from 'sharp';
import {
  createBarber,
  createSalon,
  randomPhone,
  registerCustomer,
  salonQuery,
  SalonFixture,
  staffLogin,
  testConfig,
  TestContext,
} from './helpers';
import { authedAgent, startManagerApp } from './manager-helpers';

async function tinyPng(): Promise<Buffer> {
  return sharp({ create: { width: 20, height: 20, channels: 3, background: { r: 10, g: 20, b: 30 } } })
    .withMetadata({ exif: { IFD0: { Make: 'TestCam' } } as any })
    .png()
    .toBuffer();
}

describe('manager features (profile, catalog, schedules, reports, customer admin)', () => {
  let ctx: TestContext;
  let S: SalonFixture;
  let barber: { id: string; username: string };

  beforeAll(async () => {
    ctx = await startManagerApp(testConfig());
    S = await createSalon(ctx, 'Manager Features Salon');
    barber = await createBarber(ctx, S);
  });
  afterAll(async () => ctx.close());

  const mgr = () => authedAgent(ctx, S.manager.accessToken);

  // ─── Profile ──────────────────────────────────────────────────────────────
  describe('profile', () => {
    it('gets and updates the profile (partial update, validation)', async () => {
      const got = await mgr().get('/v1/manager/profile');
      expect(got.status).toBe(200);
      expect(got.body.name).toBe('Manager Features Salon');

      const upd = await mgr().put('/v1/manager/profile').send({
        about: 'أفضل صالون',
        location: { lat: 24.7, lng: 46.7 },
        phone: '0500000001',
        socialLinks: [{ platform: 'instagram', url: 'https://instagram.com/salon' }],
      });
      expect(upd.status).toBe(200);
      expect(upd.body.about).toBe('أفضل صالون');
      expect(upd.body.location).toEqual({ lat: 24.7, lng: 46.7 });
      expect(upd.body.socialLinks).toHaveLength(1);
      // name untouched by the partial update
      expect(upd.body.name).toBe('Manager Features Salon');

      const bad = await mgr().put('/v1/manager/profile').send({ socialLinks: [{ platform: 'x', url: 'not-a-url' }] });
      expect(bad.status).toBe(400);
      expect(bad.body.error.code).toBe('VALIDATION_FAILED');
    });

    it('rejects barbers and unauthenticated requests', async () => {
      const login = await staffLogin(ctx, S.code, barber.username);
      const asBarber = await ctx.http().get('/v1/manager/profile').set('Authorization', `Bearer ${login.body.accessToken}`);
      expect(asBarber.status).toBe(403);
      const anon = await ctx.http().get('/v1/manager/profile');
      expect(anon.status).toBe(401);
    });

    it('is isolated across salons', async () => {
      const other = await createSalon(ctx, 'Other Salon Profile');
      await authedAgent(ctx, other.manager.accessToken).put('/v1/manager/profile').send({ about: 'other salon about' });
      const mine = await mgr().get('/v1/manager/profile');
      expect(mine.body.about).not.toBe('other salon about');
    });
  });

  // ─── Photos & logo (image upload rules, design §7) ─────────────────────────
  describe('photos & logo', () => {
    it('accepts a valid PNG, strips EXIF, and serves it publicly once the salon is active', async () => {
      const png = await tinyPng();
      const res = await mgr().post('/v1/manager/photos').attach('file', png, 'photo.png');
      expect(res.status).toBe(201);
      expect(res.body.position).toBe(1);

      const served = await ctx.http().get(`/v1/media/${S.code}/${res.body.path.split('/')[1]}`);
      expect(served.status).toBe(200);
      expect(served.headers['content-type']).toContain('image/png');
      const meta = await sharp(served.body as Buffer).metadata();
      expect(meta.exif).toBeUndefined();

      const del = await mgr().delete(`/v1/manager/photos/${res.body.id}`);
      expect(del.status).toBe(200);
      const gone = await ctx.http().get(`/v1/media/${S.code}/${res.body.path.split('/')[1]}`);
      expect(gone.status).toBe(404);
    });

    it('rejects a non-image, an SVG in disguise, and an oversized upload', async () => {
      const notImage = await mgr().post('/v1/manager/photos').attach('file', Buffer.from('hello world'), 'x.png');
      expect(notImage.status).toBe(400);

      const svg = await mgr().post('/v1/manager/photos').attach('file', Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"></svg>'), { filename: 'x.svg', contentType: 'image/svg+xml' });
      expect(svg.status).toBe(400);

      const big = Buffer.alloc(6 * 1024 * 1024, 1);
      const oversize = await mgr().post('/v1/manager/photos').attach('file', big, 'huge.png');
      expect([400, 413]).toContain(oversize.status);
    });

    it('caps the gallery at 6 photos', async () => {
      const s2 = await createSalon(ctx, 'Photo Limit Salon');
      const m2 = () => authedAgent(ctx, s2.manager.accessToken);
      for (let i = 0; i < 6; i++) {
        const r = await m2().post('/v1/manager/photos').attach('file', await tinyPng(), `p${i}.png`);
        expect(r.status).toBe(201);
      }
      const seventh = await m2().post('/v1/manager/photos').attach('file', await tinyPng(), 'p6.png');
      expect(seventh.status).toBe(409);
      expect(seventh.body.error.code).toBe('PHOTOS_LIMIT_REACHED');
    });

    it('sets and clears the logo', async () => {
      const set = await mgr().post('/v1/manager/profile/logo').attach('file', await tinyPng(), 'logo.png');
      expect(set.status).toBe(201);
      const del = await mgr().delete('/v1/manager/profile/logo');
      expect(del.status).toBe(200);
    });
  });

  // ─── Services & catalog ─────────────────────────────────────────────────────
  describe('services & catalog', () => {
    it('creates a bookable service and a linked catalog item, then keeps them in sync', async () => {
      const svc = await mgr().post('/v1/manager/services').send({ name: 'قص شعر', durationMinutes: 30, price: 4000 });
      expect(svc.status).toBe(201);

      const item = await mgr().post('/v1/manager/catalog').send({ kind: 'service', name: 'قص شعر', price: 4000, serviceId: svc.body.id, features: ['سريع'] });
      expect(item.status).toBe(201);
      expect(item.body.serviceId).toBe(svc.body.id);

      const upd = await mgr().put(`/v1/manager/catalog/${item.body.id}`).send({ price: 5000 });
      expect(upd.status).toBe(200);
      const svcAfter = await mgr().get('/v1/manager/services');
      expect(Number(svcAfter.body.find((s: any) => s.id === svc.body.id).price)).toBe(5000);
    });

    it('creates a product catalog item with no linked service', async () => {
      const item = await mgr().post('/v1/manager/catalog').send({ kind: 'product', name: 'شامبو', price: 2500 });
      expect(item.status).toBe(201);
      expect(item.body.serviceId).toBeNull();
    });

    it('rejects a service-kind item with neither serviceId nor durationMinutes', async () => {
      const item = await mgr().post('/v1/manager/catalog').send({ kind: 'service', name: 'بلا مدة' });
      expect(item.status).toBe(400);
    });

    it('rejects DELETE on a service used by a booking', async () => {
      const svc = await mgr().post('/v1/manager/services').send({ name: 'صبغة', durationMinutes: 45, price: 6000 });
      await salonQuery(ctx, S.dbName, "INSERT INTO customers (name, phone) VALUES ('ز', '0511111111')");
      const [c] = await salonQuery<{ id: string }>(ctx, S.dbName, "SELECT id FROM customers WHERE phone = '0511111111'");
      const [b] = await salonQuery<{ id: string }>(
        ctx,
        S.dbName,
        `INSERT INTO bookings (customer_id, staff_id, kind, status, source, work_date) VALUES ($1, $2, 'queue', 'waiting', 'barber', current_date) RETURNING id`,
        [c!.id, barber.id],
      );
      await salonQuery(
        ctx,
        S.dbName,
        `INSERT INTO booking_services (booking_id, service_id, name_snapshot, price_minor, duration_minutes_snapshot) VALUES ($1, $2, 'صبغة', 6000, 45)`,
        [b!.id, svc.body.id],
      );
      const del = await mgr().delete(`/v1/manager/services/${svc.body.id}`);
      expect(del.status).toBe(409);
    });
  });

  // ─── Schedules, breaks, absences ────────────────────────────────────────────
  describe('schedules & breaks', () => {
    it('upserts a salon default and a per-barber override, including a midnight-crossing shift', async () => {
      const def = await mgr().put('/v1/manager/schedules').send({ staffId: null, weekday: 0, opensAt: '09:00', closesAt: '22:00' });
      expect(def.status).toBe(200);
      const overnight = await mgr().put('/v1/manager/schedules').send({ staffId: barber.id, weekday: 5, opensAt: '20:00', closesAt: '02:00' });
      expect(overnight.status).toBe(200);
      expect(overnight.body.closesAt < overnight.body.opensAt).toBe(true);

      const list = await mgr().get('/v1/manager/schedules');
      expect(list.body.some((r: any) => r.staffId === null && r.weekday === 0)).toBe(true);
      expect(list.body.some((r: any) => r.staffId === barber.id && r.weekday === 5)).toBe(true);
    });

    it('rejects opensAt === closesAt', async () => {
      const bad = await mgr().put('/v1/manager/schedules').send({ staffId: null, weekday: 1, opensAt: '09:00', closesAt: '09:00' });
      expect(bad.status).toBe(400);
    });

    it('creates a recurring break, rejects an overlapping one, and supports walk_in_only + "all"', async () => {
      const b1 = await mgr().post('/v1/manager/breaks').send({ staffId: barber.id, type: 'rest', startTime: '13:00', endTime: '13:30' });
      expect(b1.status).toBe(201);
      const overlap = await mgr().post('/v1/manager/breaks').send({ staffId: barber.id, type: 'prayer', startTime: '13:15', endTime: '13:45' });
      expect(overlap.status).toBe(409);

      const barber2 = await createBarber(ctx, S);
      const all = await mgr().post('/v1/manager/breaks').send({ staffId: 'all', type: 'walk_in_only', startTime: '16:00', endTime: '17:00' });
      expect(all.status).toBe(201);
      expect(all.body.length).toBeGreaterThanOrEqual(2);
      const forBarber2 = all.body.find((br: any) => br.staffId === barber2.id);
      expect(forBarber2?.type).toBe('walk_in_only');
    });

    it('records and removes an absence', async () => {
      const abs = await mgr().post('/v1/manager/absences').send({ staffId: barber.id, workDate: '2026-10-01', reason: 'إجازة' });
      expect(abs.status).toBe(201);
      const del = await mgr().delete(`/v1/manager/absences/${abs.body.id}`);
      expect(del.status).toBe(200);
    });
  });

  // ─── Reports ─────────────────────────────────────────────────────────────
  describe('reports', () => {
    it('computes revenue, visits and ETA accuracy on a small fixture', async () => {
      const s = await createSalon(ctx, 'Reports Salon');
      const m = () => authedAgent(ctx, s.manager.accessToken);
      const b = await createBarber(ctx, s);
      const svc = await m().post('/v1/manager/services').send({ name: 'قص', durationMinutes: 30, price: 3000 });

      await salonQuery(ctx, s.dbName, "INSERT INTO customers (name, phone) VALUES ('ز1', '0522222221')");
      const [c] = await salonQuery<{ id: string }>(ctx, s.dbName, "SELECT id FROM customers WHERE phone = '0522222221'");
      const workDate = '2026-09-20';
      const originalEta = `${workDate}T10:00:00Z`;
      const actualStart = `${workDate}T10:20:00Z`; // 20 min late → ETA accuracy sample
      const actualEnd = `${workDate}T10:50:00Z`; // 30 actual minutes vs 30 base
      const [booking] = await salonQuery<{ id: string }>(
        ctx,
        s.dbName,
        `INSERT INTO bookings (customer_id, staff_id, kind, status, source, work_date, original_expected_start, actual_start, actual_end)
         VALUES ($1, $2, 'queue', 'done', 'barber', $3, $4, $5, $6) RETURNING id`,
        [c!.id, b.id, workDate, originalEta, actualStart, actualEnd],
      );
      await salonQuery(
        ctx,
        s.dbName,
        `INSERT INTO booking_services (booking_id, service_id, name_snapshot, price_minor, duration_minutes_snapshot) VALUES ($1, $2, 'قص', 3000, 30)`,
        [booking!.id, svc.body.id],
      );
      await salonQuery(
        ctx,
        s.dbName,
        `INSERT INTO payments (booking_id, amount_minor, status, confirmed_by_staff_id, confirmed_at) VALUES ($1, 3000, 'confirmed', $2, now())`,
        [booking!.id, b.id],
      );

      const rep = await m().get(`/v1/manager/reports?from=${workDate}&to=${workDate}`);
      expect(rep.status).toBe(200);
      expect(rep.body.revenue.total.confirmed).toBe(3000);
      const barberVisits = rep.body.visits.find((v: any) => v.staffId === b.id);
      expect(barberVisits.done).toBe(1);
      const eta = rep.body.etaAccuracy.find((x: any) => x.staffId === b.id);
      expect(eta.meanAbsMinutes).toBeCloseTo(20, 0);
      const dur = rep.body.durationVsBase.find((x: any) => x.staffId === b.id);
      expect(dur.avgActualMinutes).toBeCloseTo(30, 0);
      expect(dur.avgBaseMinutes).toBe(30);
      expect(rep.body.topServices[0].name).toBe('قص');
      expect(rep.body.pendingItems.unconfirmedPayments).toBeGreaterThanOrEqual(0);
    });

    it('rejects invalid ranges and non-managers', async () => {
      const bad = await mgr().get('/v1/manager/reports?from=2026-13-01&to=2026-09-01');
      expect(bad.status).toBe(400);
      const login = await staffLogin(ctx, S.code, barber.username);
      const asBarber = await ctx.http().get('/v1/manager/reports?from=2026-09-01&to=2026-09-30').set('Authorization', `Bearer ${login.body.accessToken}`);
      expect(asBarber.status).toBe(403);
    });
  });

  // ─── Customer admin: link walk-in, phone disputes (ق20) ─────────────────────
  describe('customer admin', () => {
    it('links a walk-in to an account and audits it', async () => {
      const phone = randomPhone();
      await salonQuery(ctx, S.dbName, "INSERT INTO customers (name, phone) VALUES ('حاضر', $1)", [phone]);
      const reg = await registerCustomer(ctx, S.code, phone);
      expect(reg.status).toBe(201);
      const [walkIn] = await salonQuery<{ id: string }>(ctx, S.dbName, 'SELECT id FROM customers WHERE phone = $1 AND password_hash IS NULL', [phone]);

      const link = await mgr().post(`/v1/manager/customers/${reg.body.account.id}/link-walkin`).send({ walkInId: walkIn!.id });
      expect(link.status).toBe(200);
      const [after] = await salonQuery<{ linked_walk_in_id: string }>(ctx, S.dbName, 'SELECT linked_walk_in_id FROM customers WHERE id = $1', [reg.body.account.id]);
      expect(after!.linked_walk_in_id).toBe(walkIn!.id);

      const [audit] = await salonQuery(ctx, S.dbName, "SELECT * FROM audit_log WHERE action = 'customer.walkin_linked' ORDER BY id DESC LIMIT 1");
      expect(audit).toBeDefined();
    });

    it('lists and resolves an ambiguous phone dispute', async () => {
      const phone = randomPhone();
      await salonQuery(ctx, S.dbName, "INSERT INTO customers (name, phone) VALUES ('حاضر1', $1), ('حاضر2', $1)", [phone]);
      const reg = await registerCustomer(ctx, S.code, phone);
      expect(reg.status).toBe(201);

      const disputes = await mgr().get('/v1/manager/phone-disputes');
      expect(disputes.status).toBe(200);
      const d = disputes.body.find((x: any) => x.phone === phone);
      expect(d.walkIns).toHaveLength(2);

      const resolve = await mgr().post(`/v1/manager/phone-disputes/${reg.body.account.id}/resolve`).send({ walkInId: d.walkIns[0].id });
      expect(resolve.status).toBe(200);
    });
  });
});

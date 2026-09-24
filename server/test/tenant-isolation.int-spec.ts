import * as jwt from 'jsonwebtoken';
import {
  createBarber, createSalon, randomPhone, registerCustomer, SalonFixture, salonQuery, staffLogin, startApp, TestContext,
} from './helpers';

/**
 * Cross-tenant isolation (design §7 "عزل الصالونات"): the salon is taken ONLY from the verified
 * access token. A token for salon A must never read or write salon B — whatever the request says.
 */
describe('tenant isolation', () => {
  let ctx: TestContext;
  let A: SalonFixture;
  let B: SalonFixture;
  let barberA: { id: string; username: string };
  let barberB: { id: string; username: string };
  let customerB: string;
  const auth = (t: string) => ({ Authorization: `Bearer ${t}` });

  beforeAll(async () => {
    ctx = await startApp();
    A = await createSalon(ctx, 'صالون ألف');
    B = await createSalon(ctx, 'صالون باء');
    barberA = await createBarber(ctx, A, 'samename');
    barberB = await createBarber(ctx, B, 'samename'); // same username in another salon is fine
    const phone = randomPhone();
    customerB = (await registerCustomer(ctx, B.code, phone)).body.account.id;
  });
  afterAll(() => ctx.close());

  it('lists only the token salon staff, ignoring crafted headers, query and body', async () => {
    const res = await ctx
      .http()
      .get(`/v1/manager/staff?salonId=${B.id}&salonCode=${B.code}&salon=${B.code}`)
      .set(auth(A.manager.accessToken))
      .set('X-Salon-Id', B.id)
      .set('X-Salon-Code', B.code)
      .set('X-Tenant', B.dbName)
      .send({ salonId: B.id, salonCode: B.code });
    expect(res.status).toBe(200);
    const ids = res.body.map((s: { id: string }) => s.id);
    expect(ids).toContain(barberA.id);
    expect(ids).toContain(A.manager.id);
    expect(ids).not.toContain(barberB.id);
    expect(ids).not.toContain(B.manager.id);
  });

  it('cannot write to another salon by id (staff update, reset codes, customer actions)', async () => {
    const h = auth(A.manager.accessToken);
    const r1 = await ctx.http().put(`/v1/manager/staff/${barberB.id}`).set(h).set('X-Salon-Id', B.id).send({ active: false });
    expect(r1.status).toBe(404);
    const r2 = await ctx.http().post(`/v1/manager/staff/${barberB.id}/reset-code`).set(h).send({ salonCode: B.code });
    expect(r2.status).toBe(404);
    const r3 = await ctx.http().post(`/v1/manager/customers/${customerB}/suspend`).set(h).send({ salonId: B.id });
    expect(r3.status).toBe(404);
    const r4 = await ctx.http().post(`/v1/manager/customers/${customerB}/reset-code`).set(h);
    expect(r4.status).toBe(404);
    // Nothing changed in B.
    const [b] = await salonQuery(ctx, B.dbName, 'SELECT active FROM staff WHERE id = $1', [barberB.id]);
    expect(b.active).toBe(true);
    const [c] = await salonQuery(ctx, B.dbName, 'SELECT status FROM customers WHERE id = $1', [customerB]);
    expect(c.status).toBe('active');
    expect(await salonQuery(ctx, B.dbName, 'SELECT 1 FROM reset_codes')).toHaveLength(0);
  });

  it('settings writes land only in the token salon', async () => {
    const res = await ctx
      .http()
      .put('/v1/manager/settings')
      .set(auth(A.manager.accessToken))
      .set('X-Salon-Id', B.id)
      .send({ requireAccountApproval: true });
    expect(res.status).toBe(200);
    const [a] = await salonQuery(ctx, A.dbName, 'SELECT require_account_approval AS v FROM settings');
    const [b] = await salonQuery(ctx, B.dbName, 'SELECT require_account_approval AS v FROM settings');
    expect(a.v).toBe(true);
    expect(b.v).toBe(false);
    await ctx.http().put('/v1/manager/settings').set(auth(A.manager.accessToken)).send({ requireAccountApproval: false });
  });

  it('rejects a token whose salon id was tampered with', async () => {
    const [h, , s] = A.manager.accessToken.split('.');
    const payload = { ...(jwt.decode(A.manager.accessToken) as object), sid: B.id };
    const forged = `${h}.${Buffer.from(JSON.stringify(payload)).toString('base64url')}.${s}`;
    expect((await ctx.http().get('/v1/manager/staff').set(auth(forged))).status).toBe(401);
  });

  it('rejects unsigned / foreign-key tokens', async () => {
    const claims = jwt.decode(A.manager.accessToken) as jwt.JwtPayload;
    const none = jwt.sign({ ...claims, sid: B.id }, '', { algorithm: 'none' as jwt.Algorithm });
    expect((await ctx.http().get('/v1/manager/staff').set(auth(none))).status).toBe(401);
    const foreign = jwt.sign({ ...claims, sid: B.id }, 'attacker-secret-attacker-secret-attacker!', { algorithm: 'HS256' });
    expect((await ctx.http().get('/v1/manager/staff').set(auth(foreign))).status).toBe(401);
  });

  it('even a validly signed token for salon B carrying a salon-A subject gets nothing (subject must exist in B)', async () => {
    const claims = jwt.decode(A.manager.accessToken) as jwt.JwtPayload;
    const { iat: _i, exp: _e, ...rest } = claims;
    const crossSigned = jwt.sign({ ...rest, sid: B.id }, ctx.config.auth.accessSecret, { algorithm: 'HS256', expiresIn: 60 });
    const res = await ctx.http().get('/v1/manager/staff').set(auth(crossSigned));
    expect(res.status).toBe(401);
  });

  it('refresh tokens are bound to their salon too', async () => {
    const claims = jwt.decode(A.manager.refreshToken) as jwt.JwtPayload;
    const { iat: _i, exp: _e, ...rest } = claims;
    const crossSigned = jwt.sign({ ...rest, sid: B.id }, ctx.config.auth.refreshSecret, { algorithm: 'HS256', expiresIn: 60 });
    const res = await ctx.http().post('/v1/auth/refresh').send({ refreshToken: crossSigned, salonCode: B.code });
    expect(res.status).toBe(401);
  });

  it('accounts are per salon: A credentials do not open B', async () => {
    expect((await staffLogin(ctx, B.code, A.manager.username)).status).toBe(401);
    // Same username in both salons → each login lands in its own salon.
    const la = await staffLogin(ctx, A.code, 'samename');
    const lb = await staffLogin(ctx, B.code, 'samename');
    expect(la.status).toBe(200);
    expect(lb.status).toBe(200);
    expect(la.body.account.id).toBe(barberA.id);
    expect(lb.body.account.id).toBe(barberB.id);
    expect(la.body.salon.code).toBe(A.code);
  });

  it('customer and barber tokens cannot reach manager endpoints', async () => {
    const cust = await registerCustomer(ctx, A.code, randomPhone());
    expect((await ctx.http().get('/v1/manager/staff').set(auth(cust.body.accessToken))).status).toBe(403);
    const barber = await staffLogin(ctx, A.code, 'samename');
    expect((await ctx.http().get('/v1/manager/customers').set(auth(barber.body.accessToken))).status).toBe(403);
    expect((await ctx.http().get('/v1/auth/session').set(auth(cust.body.accessToken))).body.salon.code).toBe(A.code);
  });

  it('fails closed if the directory maps a salon to another salon database', async () => {
    const d = await ctx.pools.adminClient(ctx.config.db.directoryDbName);
    try {
      // Simulate a corrupted directory: B now points at A's database.
      await d.query("UPDATE salons SET db_name = $2 || '_x' WHERE id = $1", [A.id, A.dbName]);
      await d.query('UPDATE salons SET db_name = $2 WHERE id = $1', [B.id, A.dbName]);
      const res = await ctx.http().get('/v1/manager/staff').set(auth(B.manager.accessToken));
      expect(res.status).not.toBe(200);
      expect(JSON.stringify(res.body)).not.toContain(barberA.id);
    } finally {
      await d.query('UPDATE salons SET db_name = $2 WHERE id = $1', [B.id, B.dbName]);
      await d.query('UPDATE salons SET db_name = $2 WHERE id = $1', [A.id, A.dbName]);
      await d.end();
    }
    expect((await ctx.http().get('/v1/manager/staff').set(auth(B.manager.accessToken))).status).toBe(200);
  });

  it('only active salons are visible to customers; suspension cuts existing sessions', async () => {
    const P = await createSalon(ctx, 'صالون معلق', { activate: false });
    expect((await ctx.http().get(`/v1/salons/${P.code}`)).status).toBe(404);
    expect((await registerCustomer(ctx, P.code, randomPhone())).status).toBe(404);
    // Owner can already sign in to prepare the salon while pending.
    expect((await staffLogin(ctx, P.code, P.manager.username)).status).toBe(200);

    await ctx.vendor.activate(P.code);
    const pub = await ctx.http().get(`/v1/salons/${P.code.toLowerCase()}`);
    expect(pub.status).toBe(200);
    expect(pub.body).toMatchObject({ code: P.code, name: 'صالون معلق', currency: 'SAR' });
    expect(JSON.stringify(pub.body)).not.toMatch(/password|username|db_name|dbName/);

    const cust = await registerCustomer(ctx, P.code, randomPhone());
    expect(cust.status).toBe(201);
    await ctx.vendor.suspend(P.code);
    expect((await ctx.http().get(`/v1/salons/${P.code}`)).status).toBe(404);
    expect((await ctx.http().get('/v1/auth/session').set(auth(cust.body.accessToken))).status).toBe(401);
    expect((await ctx.http().get('/v1/manager/staff').set(auth(P.manager.accessToken))).status).toBe(401);
    const login = await staffLogin(ctx, P.code, P.manager.username);
    expect(login.status).toBe(403);
    expect(login.body.error.code).toBe('SALON_SUSPENDED');
  });
});

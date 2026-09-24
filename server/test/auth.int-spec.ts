import {
  createBarber, createSalon, CUSTOMER_PW, randomPhone, registerCustomer, SalonFixture, salonQuery, sleep, STAFF_PW,
  staffLogin, startApp, testConfig, TestContext,
} from './helpers';

const auth = (t: string) => ({ Authorization: `Bearer ${t}` });

describe('authentication & sessions', () => {
  let ctx: TestContext;
  let S: SalonFixture;

  beforeAll(async () => {
    ctx = await startApp(testConfig({ BACKOFF_FREE_ATTEMPTS: '2', BACKOFF_BASE_MS: '1000' }));
    S = await createSalon(ctx, 'Raha Salon');
  });
  afterAll(() => ctx.close());

  describe('staff login', () => {
    it('logs in with salon code + username + password and returns the contract session shape', async () => {
      const res = await staffLogin(ctx, S.code.toLowerCase(), S.manager.username.toUpperCase());
      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({ role: 'manager', accessTokenExpiresIn: 900, salon: { code: S.code, status: 'active' } });
      expect(typeof res.body.accessToken).toBe('string');
      expect(typeof res.body.refreshToken).toBe('string');
      expect(JSON.stringify(res.body)).not.toContain(STAFF_PW);
      const audit = await salonQuery(ctx, S.dbName, "SELECT * FROM audit_log WHERE action = 'staff.login' AND actor_id = $1", [S.manager.id]);
      expect(audit.length).toBeGreaterThan(0);
      expect(JSON.stringify(audit)).not.toContain(STAFF_PW);
    });

    it('rejects bad credentials with a generic error', async () => {
      const wrongPw = await staffLogin(ctx, S.code, S.manager.username, 'nope-nope-nope', '10.0.0.1');
      const noUser = await staffLogin(ctx, S.code, 'nobody', STAFF_PW, '10.0.0.1');
      const noSalon = await staffLogin(ctx, 'ZZZZ-99', S.manager.username, STAFF_PW, '10.0.0.1');
      for (const r of [wrongPw, noUser, noSalon]) {
        expect(r.status).toBe(401);
        expect(r.body).toEqual({ error: { code: 'INVALID_CREDENTIALS', message: expect.any(String) } });
      }
    });

    it('enforces staff password length ≥ 10', async () => {
      const res = await ctx
        .http()
        .post('/v1/manager/staff')
        .set(auth(S.manager.accessToken))
        .send({ name: 'x', username: 'shortpw', password: '123456789', role: 'barber' });
      expect(res.status).toBe(400);
      expect(res.body.error.code).toBe('WEAK_PASSWORD');
    });
  });

  describe('progressive backoff (per account + IP, no hard lockout)', () => {
    it('delays after repeated failures, even for the right password, then recovers', async () => {
      const b = await createBarber(ctx, S);
      const ip = '203.0.113.7';
      for (let i = 0; i < 3; i++) expect((await staffLogin(ctx, S.code, b.username, 'wrong-password!', ip)).status).toBe(401);
      const blocked = await staffLogin(ctx, S.code, b.username, STAFF_PW, ip);
      expect(blocked.status).toBe(429);
      expect(blocked.body.error.code).toBe('LOGIN_BACKOFF');
      expect(Number(blocked.headers['retry-after'])).toBeGreaterThanOrEqual(1);

      // The barber on another device/IP is not locked out by the attacker.
      expect((await staffLogin(ctx, S.code, b.username, STAFF_PW, '198.51.100.20')).status).toBe(200);

      await sleep(1100);
      expect((await staffLogin(ctx, S.code, b.username, STAFF_PW, ip)).status).toBe(200);
      // Success clears the account+IP counter.
      expect((await staffLogin(ctx, S.code, b.username, 'wrong-password!', ip)).status).toBe(401);
      const [row] = await salonQuery(ctx, S.dbName, 'SELECT failed_login_count FROM staff WHERE id = $1', [b.id]);
      expect(row.failed_login_count).toBe(1);
    });

    it('applies to customers as well', async () => {
      const phone = randomPhone();
      await registerCustomer(ctx, S.code, phone);
      const ip = '203.0.113.8';
      const login = (pw: string) =>
        ctx.http().post('/v1/auth/customer/login').set('X-Forwarded-For', ip).send({ salonCode: S.code, phone, password: pw });
      for (let i = 0; i < 3; i++) expect((await login('bad-password')).status).toBe(401);
      const r = await login(CUSTOMER_PW);
      expect(r.status).toBe(429);
      expect(r.headers['retry-after']).toBeDefined();
    });
  });

  describe('customers', () => {
    it('register → active by default; min password length 8; an existing phone is never revealed (L4)', async () => {
      const phone = randomPhone();
      expect((await registerCustomer(ctx, S.code, phone, '1234567')).body.error.code).toBe('WEAK_PASSWORD');
      const r = await registerCustomer(ctx, S.code, phone);
      expect(r.status).toBe(201);
      expect(r.body).toMatchObject({ role: 'customer', account: { status: 'active' } });
      // Review L4: same number, other password → the generic REGISTRATION_FAILED (no "phone taken")…
      const dup = await registerCustomer(ctx, S.code, phone.replace(/^05/, '05 '), 'another-pass-1');
      expect(dup.status).toBe(409);
      expect(dup.body.error.code).toBe('REGISTRATION_FAILED');
      expect(JSON.stringify(dup.body)).not.toMatch(/PHONE|مسجل/);
      // …and with the account's own password it simply signs in to that account.
      const again = await registerCustomer(ctx, S.code, phone.replace(/^05/, '05 '));
      expect(again.status).toBe(201);
      expect(again.body.account.id).toBe(r.body.account.id);
      const login = await ctx.http().post('/v1/auth/customer/login').send({ salonCode: S.code, phone: '٠' + phone.slice(1), password: CUSTOMER_PW });
      expect(login.status).toBe(200);
    });

    it('honours "require approval": pending until a manager approves; suspension blocks', async () => {
      const m = auth(S.manager.accessToken);
      await ctx.http().put('/v1/manager/settings').set(m).send({ requireAccountApproval: true }).expect(200);
      const phone = randomPhone();
      const reg = await registerCustomer(ctx, S.code, phone);
      expect(reg.body.account.status).toBe('pending');
      const id = reg.body.account.id;
      const session = await ctx.http().get('/v1/auth/session').set(auth(reg.body.accessToken));
      expect(session.body.accountStatus).toBe('pending');

      const pending = await ctx.http().get('/v1/manager/customers?status=pending').set(m);
      expect(pending.body.map((c: { id: string }) => c.id)).toContain(id);
      await ctx.http().post(`/v1/manager/customers/${id}/approve`).set(m).expect(200);
      const again = await ctx.http().post('/v1/auth/customer/login').send({ salonCode: S.code, phone, password: CUSTOMER_PW });
      expect(again.body.account.status).toBe('active');

      await ctx.http().post(`/v1/manager/customers/${id}/suspend`).set(m).expect(200);
      expect((await ctx.http().get('/v1/auth/session').set(auth(again.body.accessToken))).status).toBe(401);
      const blocked = await ctx.http().post('/v1/auth/customer/login').send({ salonCode: S.code, phone, password: CUSTOMER_PW });
      expect(blocked.status).toBe(403);
      expect(blocked.body.error.code).toBe('ACCOUNT_SUSPENDED');
      const actions = (await salonQuery(ctx, S.dbName, 'SELECT action FROM audit_log WHERE target_id = $1', [id])).map((r) => r.action);
      expect(actions).toEqual(expect.arrayContaining(['customer.registered', 'customer.approved', 'customer.suspended']));
      await ctx.http().put('/v1/manager/settings').set(m).send({ requireAccountApproval: false }).expect(200);
    });
  });

  describe('refresh-token rotation', () => {
    it('rotates, and detects reuse by revoking the whole family', async () => {
      const login = await staffLogin(ctx, S.code, S.manager.username);
      const r1 = login.body.refreshToken;
      const rot = await ctx.http().post('/v1/auth/refresh').send({ refreshToken: r1 });
      expect(rot.status).toBe(200);
      const r2 = rot.body.refreshToken;
      expect(r2).not.toBe(r1);
      expect((await ctx.http().get('/v1/auth/session').set(auth(rot.body.accessToken))).status).toBe(200);

      // Replay of the rotated token → reuse detected.
      const reuse = await ctx.http().post('/v1/auth/refresh').send({ refreshToken: r1 });
      expect(reuse.status).toBe(401);
      expect(reuse.body.error.code).toBe('REFRESH_TOKEN_REUSED');
      // The legitimate newest token and the family's access tokens are dead too.
      expect((await ctx.http().post('/v1/auth/refresh').send({ refreshToken: r2 })).status).toBe(401);
      expect((await ctx.http().get('/v1/auth/session').set(auth(rot.body.accessToken))).status).toBe(401);
      const audit = await salonQuery(ctx, S.dbName, "SELECT 1 FROM audit_log WHERE action = 'session.refresh_reuse_detected'");
      expect(audit.length).toBeGreaterThan(0);
      // Other sessions of the same account are unaffected.
      expect((await ctx.http().get('/v1/auth/session').set(auth(S.manager.accessToken))).status).toBe(200);
    });

    it('stores only hashes of refresh tokens', async () => {
      const login = await staffLogin(ctx, S.code, S.manager.username);
      const rows = await salonQuery(ctx, S.dbName, 'SELECT token_hash FROM refresh_tokens');
      expect(JSON.stringify(rows)).not.toContain(login.body.refreshToken);
    });

    it('rejects garbage and access tokens used as refresh tokens', async () => {
      expect((await ctx.http().post('/v1/auth/refresh').send({ refreshToken: 'garbage' })).status).toBe(401);
      expect((await ctx.http().post('/v1/auth/refresh').send({ refreshToken: S.manager.accessToken })).status).toBe(401);
      expect((await ctx.http().post('/v1/auth/refresh').send({})).status).toBe(400);
    });

    it('logout revokes the session (refresh and access)', async () => {
      const login = await staffLogin(ctx, S.code, S.manager.username);
      await ctx.http().post('/v1/auth/logout').send({ refreshToken: login.body.refreshToken }).expect(204);
      expect((await ctx.http().post('/v1/auth/refresh').send({ refreshToken: login.body.refreshToken })).status).toBe(401);
      expect((await ctx.http().get('/v1/auth/session').set(auth(login.body.accessToken))).status).toBe(401);
      await ctx.http().post('/v1/auth/logout').send({ refreshToken: 'not-a-token' }).expect(204);
    });
  });

  describe('one-time reset codes', () => {
    it('manager issues a code for a barber; using it sets a new password and revokes all sessions', async () => {
      const b = await createBarber(ctx, S);
      const oldSession = await staffLogin(ctx, S.code, b.username);
      const issued = await ctx.http().post(`/v1/manager/staff/${b.id}/reset-code`).set(auth(S.manager.accessToken));
      expect(issued.status).toBe(200);
      const code: string = issued.body.code;
      expect(code).toMatch(/^[A-Z2-9]{5}-[A-Z2-9]{5}$/);
      const stored = await salonQuery(ctx, S.dbName, 'SELECT code_hash FROM reset_codes WHERE subject_id = $1', [b.id]);
      expect(JSON.stringify(stored)).not.toContain(code);

      const reset = (c: string, pw: string) =>
        ctx.http().post('/v1/auth/reset').send({ salonCode: S.code, identifier: b.username, code: c, newPassword: pw });
      // A weak new password is refused without burning the code.
      expect((await reset(code, 'short')).body.error.code).toBe('WEAK_PASSWORD');
      expect((await reset(code.toLowerCase(), 'brand-new-password')).status).toBe(204);

      expect((await staffLogin(ctx, S.code, b.username)).status).toBe(401);
      expect((await staffLogin(ctx, S.code, b.username, 'brand-new-password')).status).toBe(200);
      expect((await ctx.http().get('/v1/auth/session').set(auth(oldSession.body.accessToken))).status).toBe(401);
      expect((await ctx.http().post('/v1/auth/refresh').send({ refreshToken: oldSession.body.refreshToken })).status).toBe(401);
      // Single use.
      expect((await reset(code, 'another-password-1')).body.error.code).toBe('INVALID_RESET_CODE');
      const actions = (await salonQuery(ctx, S.dbName, 'SELECT action FROM audit_log WHERE target_id = $1', [b.id])).map((r) => r.action);
      expect(actions).toEqual(expect.arrayContaining(['reset_code.issued', 'password.reset_with_code']));
    });

    it('works for customers by phone; a code dies after 5 wrong guesses', async () => {
      const phone = randomPhone();
      const reg = await registerCustomer(ctx, S.code, phone);
      const id = reg.body.account.id;
      const issued = await ctx.http().post(`/v1/manager/customers/${id}/reset-code`).set(auth(S.manager.accessToken));
      const code: string = issued.body.code;
      for (let i = 0; i < 5; i++) {
        const r = await ctx
          .http()
          .post('/v1/auth/reset')
          .set('X-Forwarded-For', `192.0.2.${i + 1}`)
          .send({ salonCode: S.code, identifier: phone, code: 'AAAAA-AAAAA', newPassword: 'whatever-123' });
        expect(r.body.error.code).toBe('INVALID_RESET_CODE');
      }
      const r = await ctx.http().post('/v1/auth/reset').set('X-Forwarded-For', '192.0.2.99').send({ salonCode: S.code, identifier: phone, code, newPassword: 'whatever-123' });
      expect(r.status).toBe(400);
      expect(r.body.error.code).toBe('INVALID_RESET_CODE');
    });

    it('managers cannot issue codes for managers; the vendor can', async () => {
      const m2 = await ctx
        .http()
        .post('/v1/manager/staff')
        .set(auth(S.manager.accessToken))
        .send({ name: 'M2', username: 'second_mgr', password: STAFF_PW, role: 'manager' });
      expect(m2.status).toBe(201);
      expect((await ctx.http().post(`/v1/manager/staff/${m2.body.id}/reset-code`).set(auth(S.manager.accessToken))).status).toBe(403);
      await expect(ctx.vendor.resetManagerPassword(S.code)).rejects.toThrow(/2 managers/);
      const v = await ctx.vendor.resetManagerPassword(S.code, 'second_mgr');
      const r = await ctx.http().post('/v1/auth/reset').send({ salonCode: S.code, identifier: 'second_mgr', code: v.code, newPassword: 'vendor-reset-pass' });
      expect(r.status).toBe(204);
      expect((await staffLogin(ctx, S.code, 'second_mgr', 'vendor-reset-pass')).status).toBe(200);
      const [a] = await salonQuery(ctx, S.dbName, "SELECT actor_kind FROM audit_log WHERE action = 'reset_code.issued' AND target_id = $1", [m2.body.id]);
      expect(a.actor_kind).toBe('vendor');
    });
  });

  describe('input validation & error shape', () => {
    it('returns the contract error shape for malformed input without echoing values', async () => {
      const r = await ctx.http().post('/v1/auth/staff/login').send({ salonCode: S.code, username: 'x', password: 12345 });
      expect(r.status).toBe(400);
      expect(r.body.error.code).toBe('VALIDATION_FAILED');
      expect(JSON.stringify(r.body)).not.toContain('12345');
      const bad = await ctx.http().post('/v1/auth/staff/login').set('Content-Type', 'application/json').send('{"broken"');
      expect(bad.status).toBe(400);
      expect(bad.body.error.code).toBeDefined();
      const noAuth = await ctx.http().get('/v1/manager/staff');
      expect(noAuth.body).toEqual({ error: { code: 'UNAUTHENTICATED', message: expect.any(String) } });
    });

    it('sets security headers', async () => {
      const r = await ctx.http().get('/v1/health');
      expect(r.headers['x-content-type-options']).toBe('nosniff');
      expect(r.headers['x-powered-by']).toBeUndefined();
    });
  });
});

describe('rate limiting', () => {
  let ctx: TestContext;
  let S: SalonFixture;

  beforeAll(async () => {
    const cfg = testConfig();
    ctx = await startApp(cfg);
    S = await createSalon(ctx, 'Limit Salon');
    await ctx.close();
    const limited = testConfig({ RATE_LIMITS_ENABLED: 'true' });
    limited.rateLimits.login = { ip: { limit: 3, windowMs: 60_000 }, account: { limit: 2, windowMs: 60_000 } };
    limited.rateLimits.salonRegister = { ip: { limit: 1, windowMs: 60_000 } };
    ctx = await startApp(limited);
  });
  afterAll(() => ctx.close());

  it('limits login per account across IPs and per IP across accounts', async () => {
    const tryLogin = (user: string, ip: string) =>
      ctx.http().post('/v1/auth/staff/login').set('X-Forwarded-For', ip).send({ salonCode: S.code, username: user, password: 'x' });
    expect((await tryLogin('victim', '10.1.0.1')).status).toBe(401);
    expect((await tryLogin('victim', '10.1.0.2')).status).toBe(401);
    const acct = await tryLogin('victim', '10.1.0.3');
    expect(acct.status).toBe(429);
    expect(acct.body.error.code).toBe('RATE_LIMITED');
    expect(Number(acct.headers['retry-after'])).toBeGreaterThan(0);

    for (const u of ['u1', 'u2', 'u3']) expect((await tryLogin(u, '10.2.0.1')).status).toBe(401);
    expect((await tryLogin('u4', '10.2.0.1')).status).toBe(429);
  });

  it('limits salon self-registration per IP', async () => {
    const reg = () => ctx.http().post('/v1/salons/register').set('X-Forwarded-For', '10.3.0.1').send({});
    expect((await reg()).status).toBe(400);
    expect((await reg()).status).toBe(429);
  });
});

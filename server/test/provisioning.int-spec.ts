import { SALON_CODE_RE } from '../src/common/normalize';
import { loadMigrations } from '../src/db/migrator';
import { salonQuery, startApp, STAFF_PW, TestContext } from './helpers';

describe('salon self-registration (ق37)', () => {
  let ctx: TestContext;
  beforeAll(async () => {
    ctx = await startApp();
  });
  afterAll(() => ctx.close());

  const body = (over: Record<string, unknown> = {}, owner: Record<string, unknown> = {}) => ({
    salon: { name: 'صالون الراحة', timezone: 'Asia/Riyadh', currency: 'sar', phone: '0500000001', ...over },
    owner: { name: 'صاحب الصالون', username: 'Owner_1', password: STAFF_PW, ...owner },
  });

  it('creates a pending salon with its own migrated database and the owner as manager', async () => {
    const res = await ctx.http().post('/v1/salons/register').send(body());
    expect(res.status).toBe(201);
    const { code } = res.body.salon;
    expect(code).toMatch(SALON_CODE_RE);
    expect(code.startsWith('RAHA-')).toBe(true);
    expect(res.body.salon).toMatchObject({ status: 'pending_activation', currency: 'SAR', timezone: 'Asia/Riyadh' });
    expect(res.body.session.role).toBe('manager');

    const rec = (await ctx.vendor.list('pending_activation')).find((s) => s.code === code)!;
    expect(rec.schema_version).toBe(loadMigrations('salon').length);
    const staff = await salonQuery(ctx, rec.db_name, 'SELECT username, role, password_hash FROM staff');
    expect(staff).toHaveLength(1);
    expect(staff[0]).toMatchObject({ username: 'owner_1', role: 'manager' });
    expect(staff[0].password_hash).toMatch(/^\$argon2id\$/);
    const [meta] = await salonQuery(ctx, rec.db_name, 'SELECT salon_id, salon_code FROM salon_meta');
    expect(meta).toEqual({ salon_id: rec.id, salon_code: code });
    const [profile] = await salonQuery(ctx, rec.db_name, 'SELECT name, phone FROM salon_profile');
    expect(profile).toEqual({ name: 'صالون الراحة', phone: '0500000001' });

    // A second salon with the same name gets a different code and database.
    const res2 = await ctx.http().post('/v1/salons/register').send(body());
    expect(res2.status).toBe(201);
    expect(res2.body.salon.code).not.toBe(code);
  });

  it('validates input', async () => {
    const cases = [
      body({ timezone: 'Mars/Olympus' }),
      body({ currency: 'XXXX' }),
      body({ currency: 'QQQ' }),
      body({}, { password: 'short-pw' }),
      body({}, { username: 'bad name!' }),
      body({ name: 'x' }),
    ];
    for (const b of cases) {
      const r = await ctx.http().post('/v1/salons/register').send(b);
      expect(r.status).toBe(400);
      expect(r.body.error.code).toMatch(/VALIDATION_FAILED|WEAK_PASSWORD/);
    }
  });

  it('rolls back the directory row when the database cannot be created (and never drops a foreign DB)', async () => {
    const spy = jest.spyOn(Math, 'random').mockReturnValue(0); // → code ROLL-10 on the first attempt
    const admin = await ctx.pools.adminClient();
    const dbName = `${ctx.config.db.salonDbPrefix}roll_10`;
    try {
      await admin.query(`CREATE DATABASE "${dbName}"`);
      const res = await ctx.http().post('/v1/salons/register').send(body({ name: 'Rollback Test' }, { username: 'rb_owner' }));
      expect(res.status).toBe(500);
      expect(res.body.error.code).toBe('INTERNAL_ERROR');
      expect((await ctx.vendor.list()).find((s) => s.code === 'ROLL-10')).toBeUndefined();
      const { rowCount } = await admin.query('SELECT 1 FROM pg_database WHERE datname = $1', [dbName]);
      expect(rowCount).toBe(1);
    } finally {
      spy.mockRestore();
      await admin.query(`DROP DATABASE IF EXISTS "${dbName}" WITH (FORCE)`);
      await admin.end();
    }
  });
});

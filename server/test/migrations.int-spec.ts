import { cpSync, mkdtempSync, rmSync, writeFileSync, appendFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { migrateAll, migrateDirectory } from '../src/db/migrate-all';
import { DEFAULT_MIGRATIONS_ROOT, loadMigrations, MigrationError } from '../src/db/migrator';
import { createSalon, SalonFixture, salonQuery, startApp, testConfig, TestContext } from './helpers';

/** Uses its own directory DB so the synthetic migrations below cannot affect other suites. */
describe('migration runner', () => {
  const cfg = testConfig({ DIRECTORY_DB_NAME: 'saloni_test_mig_directory', SALON_DB_PREFIX: 'saloni_test_m_' });
  let ctx: TestContext;
  let salons: SalonFixture[];
  let root: string;
  const latest = loadMigrations('salon').length;

  beforeAll(async () => {
    const { PoolManager } = await import('../src/db/pools');
    const p = new PoolManager(cfg);
    await migrateDirectory(p, cfg);
    await p.close();
    ctx = await startApp(cfg);
    salons = [];
    for (const n of ['Mig One', 'Mig Two', 'Mig Three']) salons.push(await createSalon(ctx, n));
    root = mkdtempSync(join(tmpdir(), 'saloni-mig-'));
    cpSync(DEFAULT_MIGRATIONS_ROOT, root, { recursive: true });
  });
  afterAll(async () => {
    rmSync(root, { recursive: true, force: true });
    await ctx.close();
  });

  const versions = async () => {
    const d = await ctx.pools.adminClient(cfg.db.directoryDbName);
    try {
      const { rows } = await d.query('SELECT code, schema_version FROM salons ORDER BY registered_at');
      return Object.fromEntries(rows.map((r) => [r.code, r.schema_version]));
    } finally {
      await d.end();
    }
  };

  it('provisioned salons are recorded at the latest version; re-running is a no-op', async () => {
    const v = await versions();
    for (const s of salons) expect(v[s.code]).toBe(latest);
    const r = await migrateAll(ctx.pools, cfg);
    expect(r.directory.applied).toEqual([]);
    expect(r.salons.map((s) => s.applied.length)).toEqual([0, 0, 0]);
  });

  it('stops at the first failing salon; earlier salons keep the new version, later ones are untouched', async () => {
    const [s1, s2, s3] = salons as [SalonFixture, SalonFixture, SalonFixture];
    const next = latest + 1;
    writeFileSync(
      join(root, 'salon', `${String(next).padStart(3, '0')}_probe.sql`),
      `DO $$ BEGIN
         IF (SELECT salon_code FROM salon_meta) = '${s2.code}' THEN RAISE EXCEPTION 'boom for test'; END IF;
       END $$;
       CREATE TABLE migration_probe (id int);`,
    );
    const err = await migrateAll(ctx.pools, cfg, () => undefined, root).catch((e) => e);
    expect(err).toBeInstanceOf(MigrationError);
    expect(err.database).toBe(s2.dbName);
    expect(err.version).toBe(next);

    const v = await versions();
    expect(v[s1.code]).toBe(next);
    expect(v[s2.code]).toBe(latest);
    expect(v[s3.code]).toBe(latest);
    // The failed migration was rolled back atomically.
    const probe = (db: string) => salonQuery(ctx, db, "SELECT to_regclass('migration_probe') AS t");
    expect((await probe(s1.dbName))[0].t).toBe('migration_probe');
    expect((await probe(s2.dbName))[0].t).toBeNull();
    expect((await probe(s3.dbName))[0].t).toBeNull();
    expect((await salonQuery(ctx, s2.dbName, 'SELECT max(version) AS v FROM schema_migrations'))[0].v).toBe(latest);

    // Fix the migration and re-run: everything converges.
    writeFileSync(join(root, 'salon', `${String(next).padStart(3, '0')}_probe.sql`), 'CREATE TABLE IF NOT EXISTS migration_probe (id int);');
    // s1 already applied the old text → checksum mismatch must be reported, not silently ignored.
    const mismatch = await migrateAll(ctx.pools, cfg, () => undefined, root).catch((e) => e);
    expect(mismatch).toBeInstanceOf(MigrationError);
    expect(mismatch.message).toMatch(/checksum mismatch/);
    expect(mismatch.database).toBe(s1.dbName);
  });

  it('refuses to run against a database newer than the code', async () => {
    const err = await migrateAll(ctx.pools, cfg).catch((e) => e); // real root lacks the probe migration
    expect(err).toBeInstanceOf(MigrationError);
    expect(err.message).toMatch(/unknown to this build/);
  });

  it('validates migration file numbering', () => {
    const bad = mkdtempSync(join(tmpdir(), 'saloni-bad-'));
    try {
      cpSync(DEFAULT_MIGRATIONS_ROOT, bad, { recursive: true });
      writeFileSync(join(bad, 'salon', `${String(loadMigrations('salon').length + 2).padStart(3, '0')}_gap.sql`), 'SELECT 1;');
      expect(() => loadMigrations('salon', bad)).toThrow(/without gaps/);
      appendFileSync(join(bad, 'directory', 'oops.sql'), '');
      expect(() => loadMigrations('directory', bad)).toThrow(/Bad migration file name/);
    } finally {
      rmSync(bad, { recursive: true, force: true });
    }
  });
});

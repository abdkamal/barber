import type { AppConfig } from '../config/config';
import { loadMigrations, migrateDatabase, MigrateResult, MigrationError, DEFAULT_MIGRATIONS_ROOT } from './migrator';
import { PoolManager } from './pools';
import { quoteIdent } from './sql';

export interface MigrateAllReport {
  directory: MigrateResult;
  salons: Array<MigrateResult & { code: string }>;
}

type Log = (line: string) => void;

/** Creates a database if it does not exist (direct admin connection). */
export async function ensureDatabase(pools: PoolManager, dbName: string): Promise<boolean> {
  const c = await pools.adminClient();
  try {
    const { rowCount } = await c.query('SELECT 1 FROM pg_database WHERE datname = $1', [dbName]);
    if (rowCount) return false;
    await c.query(`CREATE DATABASE ${quoteIdent(dbName)} TEMPLATE template0 ENCODING 'UTF8'`);
    return true;
  } finally {
    await c.end();
  }
}

export async function migrateDirectory(pools: PoolManager, config: AppConfig, root = DEFAULT_MIGRATIONS_ROOT): Promise<MigrateResult> {
  await ensureDatabase(pools, config.db.directoryDbName);
  const c = await pools.adminClient(config.db.directoryDbName);
  try {
    return await migrateDatabase(c, loadMigrations('directory', root), config.db.directoryDbName);
  } finally {
    await c.end();
  }
}

/** Migrates one salon database and records its version in the directory. */
export async function migrateSalon(
  pools: PoolManager,
  config: AppConfig,
  salon: { id: string; db_name: string },
  root = DEFAULT_MIGRATIONS_ROOT,
): Promise<MigrateResult> {
  const c = await pools.adminClient(salon.db_name);
  let result: MigrateResult;
  try {
    result = await migrateDatabase(c, loadMigrations('salon', root), salon.db_name);
  } finally {
    await c.end();
  }
  const d = await pools.adminClient(config.db.directoryDbName);
  try {
    await d.query('UPDATE salons SET schema_version = $2, updated_at = now() WHERE id = $1', [salon.id, result.to]);
  } finally {
    await d.end();
  }
  return result;
}

/**
 * `npm run migrate`: the directory first, then every salon database in registration order.
 * Stops at the first failure (throws MigrationError); already-migrated salons keep their new version.
 */
export async function migrateAll(pools: PoolManager, config: AppConfig, log: Log = () => undefined, root = DEFAULT_MIGRATIONS_ROOT): Promise<MigrateAllReport> {
  const directory = await migrateDirectory(pools, config, root);
  log(`directory ${directory.database}: v${directory.from} → v${directory.to}`);
  const d = await pools.adminClient(config.db.directoryDbName);
  let salons: Array<{ id: string; code: string; db_name: string }>;
  try {
    ({ rows: salons } = await d.query('SELECT id, code, db_name FROM salons ORDER BY registered_at, code'));
  } finally {
    await d.end();
  }
  const report: MigrateAllReport = { directory, salons: [] };
  for (const s of salons) {
    try {
      const r = await migrateSalon(pools, config, s, root);
      report.salons.push({ ...r, code: s.code });
      log(`salon ${s.code} (${s.db_name}): v${r.from} → v${r.to}`);
    } catch (e) {
      if (e instanceof MigrationError) throw e;
      throw new MigrationError(`salon ${s.code}: ${(e as Error).message}`, s.db_name, undefined, e);
    }
  }
  return report;
}

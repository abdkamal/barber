/**
 * npm run migrate — migrates the directory DB, then every salon DB in turn (registration order),
 * recording each salon's schema version in the directory. Stops at the first failure (exit code 1).
 */
import { loadConfig, loadDotEnv } from '../config/config';
import { migrateAll } from '../db/migrate-all';
import { MigrationError } from '../db/migrator';
import { PoolManager } from '../db/pools';

async function main(): Promise<number> {
  loadDotEnv();
  const config = loadConfig();
  const pools = new PoolManager(config);
  try {
    const r = await migrateAll(pools, config, (l) => console.log(l));
    const applied = r.salons.reduce((n, s) => n + s.applied.length, 0);
    console.log(`done: directory v${r.directory.to}, ${r.salons.length} salon database(s), ${applied} salon migration(s) applied`);
    return 0;
  } catch (e) {
    if (e instanceof MigrationError) {
      console.error(`MIGRATION FAILED on ${e.database}${e.version ? ` (version ${e.version})` : ''}: ${e.message}`);
      console.error('Stopped. Remaining databases were not migrated.');
    } else {
      console.error(`MIGRATION FAILED: ${(e as Error).message}`);
    }
    return 1;
  } finally {
    await pools.close();
  }
}

main().then((code) => process.exit(code));

import { execSync } from 'node:child_process';
import { resolve } from 'node:path';
import { Client } from 'pg';
import { migrateDirectory } from '../src/db/migrate-all';
import { PoolManager } from '../src/db/pools';
import { testConfig } from './helpers';

async function canConnect(host: string, port: number, user: string, password: string): Promise<boolean> {
  const c = new Client({ host, port, user, password, database: 'postgres', connectionTimeoutMillis: 3000 });
  try {
    await c.connect();
    await c.query('SELECT 1');
    return true;
  } catch {
    return false;
  } finally {
    await c.end().catch(() => undefined);
  }
}

/**
 * Integration tests need PostgreSQL + PgBouncer from infra/docker-compose.yml.
 * If they are not reachable we try `docker compose up -d --wait` once.
 * All databases named saloni_test_* are dropped before the run.
 */
export default async function globalSetup(): Promise<void> {
  const cfg = testConfig();
  const a = cfg.db.admin;
  const r = cfg.db.runtime;
  const up = async () =>
    (await canConnect(a.host, a.port, a.user, a.password)) && (await canConnect(r.host, r.port, r.user, r.password));
  if (!(await up())) {
    const compose = resolve(__dirname, '..', '..', 'infra', 'docker-compose.yml');
    try {
      execSync(`docker compose -f "${compose}" up -d --wait`, { stdio: 'inherit' });
    } catch {
      throw new Error('PostgreSQL/PgBouncer not reachable and `docker compose up` failed. Start infra/docker-compose.yml first.');
    }
    if (!(await up())) throw new Error('PostgreSQL/PgBouncer still not reachable after docker compose up');
  }
  const pools = new PoolManager(cfg);
  try {
    const admin = await pools.adminClient();
    try {
      const { rows } = await admin.query<{ datname: string }>(
        "SELECT datname FROM pg_database WHERE datname LIKE 'saloni\\_test\\_%'",
      );
      for (const { datname } of rows) await admin.query(`DROP DATABASE "${datname}" WITH (FORCE)`);
    } finally {
      await admin.end();
    }
    await migrateDirectory(pools, cfg);
  } finally {
    await pools.close();
  }
}

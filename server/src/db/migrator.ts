import { createHash } from 'node:crypto';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import type { Client } from 'pg';

export interface Migration {
  version: number;
  name: string;
  sql: string;
  checksum: string;
}

export type MigrationTarget = 'directory' | 'salon';

export const DEFAULT_MIGRATIONS_ROOT = resolve(__dirname, '..', '..', 'migrations');

const FILE_RE = /^(\d{3,})_([a-z0-9_]+)\.sql$/;

/** Loads NNN_name.sql files; versions must be unique and contiguous from 1. */
export function loadMigrations(target: MigrationTarget, root = DEFAULT_MIGRATIONS_ROOT): Migration[] {
  const dir = join(root, target);
  const files = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();
  const out: Migration[] = [];
  for (const f of files) {
    const m = FILE_RE.exec(f);
    if (!m) throw new Error(`Bad migration file name: ${target}/${f}`);
    const sql = readFileSync(join(dir, f), 'utf8');
    out.push({
      version: Number(m[1]),
      name: m[2]!,
      sql,
      checksum: createHash('sha256').update(sql).digest('hex'),
    });
  }
  out.sort((a, b) => a.version - b.version);
  out.forEach((mig, i) => {
    if (mig.version !== i + 1) throw new Error(`${target} migrations must be numbered 1..n without gaps (found ${mig.version} at position ${i + 1})`);
  });
  return out;
}

export class MigrationError extends Error {
  constructor(
    message: string,
    readonly database: string,
    readonly version?: number,
    override readonly cause?: unknown,
  ) {
    super(message);
    this.name = 'MigrationError';
  }
}

export interface MigrateResult {
  database: string;
  from: number;
  to: number;
  applied: number[];
}

const LOCK_KEY = 0x5a10_41; // advisory lock id for migrations (per database)

/**
 * Applies pending migrations to ONE database over a direct (non-PgBouncer) connection.
 * Each migration runs in its own transaction together with its bookkeeping row.
 * Refuses to run if an applied migration's checksum changed or the DB is newer than the code.
 */
export async function migrateDatabase(client: Client, migrations: Migration[], dbLabel: string): Promise<MigrateResult> {
  await client.query('SELECT pg_advisory_lock($1)', [LOCK_KEY]);
  try {
    await client.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
      version integer PRIMARY KEY,
      name text NOT NULL,
      checksum text NOT NULL,
      applied_at timestamptz NOT NULL DEFAULT now()
    )`);
    const { rows } = await client.query<{ version: number; checksum: string }>(
      'SELECT version, checksum FROM schema_migrations ORDER BY version',
    );
    const known = new Map(migrations.map((m) => [m.version, m]));
    for (const r of rows) {
      const m = known.get(r.version);
      if (!m) throw new MigrationError(`database is at version ${r.version}, unknown to this build`, dbLabel, r.version);
      if (m.checksum !== r.checksum) {
        throw new MigrationError(`checksum mismatch for applied migration ${r.version}_${m.name}`, dbLabel, r.version);
      }
    }
    const from = rows.length ? rows[rows.length - 1]!.version : 0;
    const applied: number[] = [];
    for (const m of migrations) {
      if (m.version <= from) continue;
      try {
        await client.query('BEGIN');
        await client.query(m.sql);
        await client.query('INSERT INTO schema_migrations (version, name, checksum) VALUES ($1, $2, $3)', [
          m.version,
          m.name,
          m.checksum,
        ]);
        await client.query('COMMIT');
        applied.push(m.version);
      } catch (e) {
        await client.query('ROLLBACK').catch(() => undefined);
        throw new MigrationError(
          `migration ${m.version}_${m.name} failed: ${(e as Error).message}`,
          dbLabel,
          m.version,
          e,
        );
      }
    }
    return { database: dbLabel, from, to: applied.length ? applied[applied.length - 1]! : from, applied };
  } finally {
    await client.query('SELECT pg_advisory_unlock($1)', [LOCK_KEY]).catch(() => undefined);
  }
}

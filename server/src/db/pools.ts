import { Client, Pool, PoolConfig } from 'pg';
import type { AppConfig } from '../config/config';
import { isValidDbName } from './sql';

/**
 * Connection factory.
 *  - runtime pools (directory + one small lazily-created pool per salon DB) go through PgBouncer;
 *  - admin clients (CREATE DATABASE, migrations) connect directly to PostgreSQL.
 * Per-tenant pools are evicted after being idle for `tenantPoolIdleTtlMs`, and the total number of
 * tenant pools is capped (least-recently-used idle pool is closed first).
 */
export class PoolManager {
  private directory?: Pool;
  private readonly tenants = new Map<string, { pool: Pool; lastUsed: number }>();
  private readonly sweeper: NodeJS.Timeout;
  private closed = false;

  constructor(private readonly config: AppConfig) {
    const every = Math.max(1_000, Math.min(60_000, Math.floor(config.db.tenantPoolIdleTtlMs / 2)));
    this.sweeper = setInterval(() => void this.evictIdle(), every);
    this.sweeper.unref();
  }

  private base(): PoolConfig {
    const r = this.config.db.runtime;
    return {
      host: r.host,
      port: r.port,
      user: r.user,
      password: r.password,
      application_name: 'saloni-server',
      connectionTimeoutMillis: 10_000,
      idleTimeoutMillis: 30_000,
    };
  }

  directoryPool(): Pool {
    if (this.closed) throw new Error('PoolManager is closed');
    if (!this.directory) {
      this.directory = new Pool({ ...this.base(), database: this.config.db.directoryDbName, max: this.config.db.directoryPoolMax });
      this.directory.on('error', () => undefined); // idle client errors are handled by pg reconnecting
    }
    return this.directory;
  }

  /** Returns (creating lazily) the runtime pool of one salon database. */
  tenantPool(dbName: string): Pool {
    if (this.closed) throw new Error('PoolManager is closed');
    if (!isValidDbName(dbName)) throw new Error('invalid tenant database name');
    const now = Date.now();
    const hit = this.tenants.get(dbName);
    if (hit) {
      hit.lastUsed = now;
      return hit.pool;
    }
    if (this.tenants.size >= this.config.db.tenantPoolsMax) this.evictLeastRecentlyUsed();
    const pool = new Pool({ ...this.base(), database: dbName, max: this.config.db.tenantPoolMax });
    pool.on('error', () => undefined);
    this.tenants.set(dbName, { pool, lastUsed: now });
    return pool;
  }

  tenantPoolCount(): number {
    return this.tenants.size;
  }

  hasTenantPool(dbName: string): boolean {
    return this.tenants.has(dbName);
  }

  /** Closes tenant pools idle for longer than the TTL (never one with checked-out clients). */
  async evictIdle(now = Date.now()): Promise<number> {
    const ttl = this.config.db.tenantPoolIdleTtlMs;
    const victims: Pool[] = [];
    for (const [name, entry] of this.tenants) {
      const busy = entry.pool.totalCount - entry.pool.idleCount > 0 || entry.pool.waitingCount > 0;
      if (!busy && now - entry.lastUsed >= ttl) {
        this.tenants.delete(name);
        victims.push(entry.pool);
      }
    }
    await Promise.allSettled(victims.map((p) => p.end()));
    return victims.length;
  }

  private evictLeastRecentlyUsed(): void {
    let oldest: [string, { pool: Pool; lastUsed: number }] | undefined;
    for (const e of this.tenants) {
      const busy = e[1].pool.totalCount - e[1].pool.idleCount > 0;
      if (!busy && (!oldest || e[1].lastUsed < oldest[1].lastUsed)) oldest = e;
    }
    if (oldest) {
      this.tenants.delete(oldest[0]);
      void oldest[1].pool.end().catch(() => undefined);
    }
  }

  /** A direct (non-pooled, not via PgBouncer) admin connection. Caller must end() it. */
  async adminClient(database?: string): Promise<Client> {
    const a = this.config.db.admin;
    const db = database ?? a.maintenanceDb;
    if (!isValidDbName(db)) throw new Error('invalid database name');
    const c = new Client({
      host: a.host,
      port: a.port,
      user: a.user,
      password: a.password,
      database: db,
      application_name: 'saloni-admin',
      connectionTimeoutMillis: 10_000,
    });
    await c.connect();
    return c;
  }

  async close(): Promise<void> {
    this.closed = true;
    clearInterval(this.sweeper);
    const all = [...this.tenants.values()].map((e) => e.pool);
    this.tenants.clear();
    if (this.directory) all.push(this.directory);
    this.directory = undefined;
    await Promise.allSettled(all.map((p) => p.end()));
  }
}

import type { PoolClient, QueryResult, QueryResultRow } from 'pg';

/** Minimal query interface implemented by pools, clients and transaction handles. */
export interface Queryable {
  query<R extends QueryResultRow = QueryResultRow>(text: string, params?: unknown[]): Promise<QueryResult<R>>;
}

const IDENT_RE = /^[a-z][a-z0-9_]{0,62}$/;

/** Quotes a database identifier after strict validation (we only ever create lowercase ascii names). */
export function quoteIdent(name: string): string {
  if (!IDENT_RE.test(name)) throw new Error(`Refusing unsafe identifier: ${JSON.stringify(name)}`);
  return `"${name}"`;
}

export function isValidDbName(name: string): boolean {
  return IDENT_RE.test(name);
}

/** Runs fn inside BEGIN/COMMIT on a checked-out client (PgBouncer transaction mode friendly). */
export async function inTransaction<T>(client: PoolClient, fn: (q: Queryable) => Promise<T>): Promise<T> {
  await client.query('BEGIN');
  try {
    const out = await fn(client);
    await client.query('COMMIT');
    return out;
  } catch (e) {
    try {
      await client.query('ROLLBACK');
    } catch {
      /* connection may be broken; the pool will discard it */
    }
    throw e;
  }
}

export function isUniqueViolation(e: unknown, constraint?: string): boolean {
  const err = e as { code?: string; constraint?: string };
  return err?.code === '23505' && (constraint === undefined || err.constraint === constraint);
}

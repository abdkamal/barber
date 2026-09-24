import type { Pool, QueryResult, QueryResultRow } from 'pg';
import { inTransaction, Queryable } from '../db/sql';
import type { SalonStatus } from '../directory/directory.repository';

const TENANT_BRAND = Symbol('tenant-bound');

/**
 * A query handle bound to one salon database (the context's pool, or a transaction on it).
 * Repositories accept only this branded type, so a raw pool/client cannot be passed by mistake.
 */
export interface TenantQueryable extends Queryable {
  readonly [TENANT_BRAND]: string; // salon id
}

/** A database handle bound to exactly one salon database. */
export interface TenantDb extends TenantQueryable {
  tx<T>(fn: (q: TenantQueryable) => Promise<T>): Promise<T>;
}

export interface TenantSalon {
  id: string;
  code: string;
  name: string;
  dbName: string;
  status: SalonStatus;
  timezone: string;
  currency: string;
}

const MINT = Symbol('TenantContext.mint');

/**
 * The tenant of the current request. It can only be minted by TenantResolver (from a verified
 * token, or from a salon code on the unauthenticated login/registration paths). Every repository
 * that touches salon data takes a TenantContext argument — there is no global/default tenant.
 */
export class TenantContext {
  readonly db: TenantDb;

  private constructor(readonly salon: TenantSalon, getPool: () => Promise<Pool>) {
    this.db = {
      [TENANT_BRAND]: salon.id,
      query: async <R extends QueryResultRow = QueryResultRow>(text: string, params?: unknown[]): Promise<QueryResult<R>> =>
        (await getPool()).query<R>(text, params),
      tx: async <T>(fn: (q: TenantQueryable) => Promise<T>): Promise<T> => {
        const client = await (await getPool()).connect();
        try {
          return await inTransaction(client, (c) =>
            fn({ [TENANT_BRAND]: salon.id, query: (text: string, params?: unknown[]) => c.query(text, params) } as TenantQueryable),
          );
        } finally {
          client.release();
        }
      },
    };
    Object.freeze(this);
  }

  get salonId(): string {
    return this.salon.id;
  }

  /** @internal only TenantResolver holds MINT. */
  static mint(key: symbol, salon: TenantSalon, getPool: () => Promise<Pool>): TenantContext {
    if (key !== MINT) throw new Error('TenantContext can only be created by TenantResolver');
    return new TenantContext(salon, getPool);
  }
}

/** @internal */
export const TENANT_MINT_KEY = MINT;

import { TenantContext, TenantQueryable } from '../tenancy/tenant-context';

export type ActorKind = 'staff' | 'customer' | 'vendor' | 'system' | 'anonymous';

export interface AuditEntry {
  actorKind: ActorKind;
  actorId?: string | null;
  action: string;
  targetKind?: string | null;
  targetId?: string | null;
  ip?: string | null;
  /** Never put secrets (passwords, tokens, codes) here. */
  details?: Record<string, unknown>;
}

/** Writes to the salon's append-only audit_log. Pass a transaction handle to make it atomic. */
export async function writeAudit(q: TenantQueryable | TenantContext, e: AuditEntry): Promise<void> {
  const db: TenantQueryable = q instanceof TenantContext ? q.db : q;
  await db.query(
    `INSERT INTO audit_log (actor_kind, actor_id, action, target_kind, target_id, ip, details)
     VALUES ($1, $2, $3, $4, $5, $6, $7)`,
    [e.actorKind, e.actorId ?? null, e.action, e.targetKind ?? null, e.targetId ?? null, e.ip ?? null, JSON.stringify(e.details ?? {})],
  );
}

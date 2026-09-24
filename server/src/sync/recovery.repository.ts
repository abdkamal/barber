import { writeAudit } from '../security/audit';
import type { TenantContext, TenantQueryable } from '../tenancy/tenant-context';

export interface RecoveredEventItem {
  id: string;
  staffId: string;
  staffName: string | null;
  eventId: string | null;
  type: string | null;
  bookingId: string | null;
  customerName: string | null;
  occurredAt: string | null;
  approximate: boolean;
  suspendedAt: string | null;
  reason: string | null;
  recoveredBy: { id: string; name: string | null } | null;
  recoveredAt: string;
  reviewedAt: string | null;
  reviewedBy: { id: string; name: string | null } | null;
}

interface Row {
  id: string;
  staff_id: string;
  staff_name: string | null;
  device_event_id: string | null;
  booking_id: string | null;
  customer_name: string | null;
  details: Record<string, unknown>;
  created_at: Date;
  resolved_at: Date | null;
  resolved_by_staff_id: string | null;
  reviewer_name: string | null;
  recoverer_id: string | null;
  recoverer_name: string | null;
}

const str = (v: unknown): string | null => (typeof v === 'string' ? v : null);

/** ق40: events a manager recovered for a suspended account, pending review (`sync_conflicts` rows). */
export const RecoveryRepo = {
  async list(q: TenantQueryable, all: boolean): Promise<RecoveredEventItem[]> {
    const { rows } = await q.query<Row>(
      `SELECT c.id, c.staff_id, s.name AS staff_name, c.device_event_id, c.booking_id, cu.name AS customer_name, c.details,
              c.created_at, c.resolved_at, c.resolved_by_staff_id, rv.name AS reviewer_name,
              de.recovered_by_staff_id AS recoverer_id, rb.name AS recoverer_name
         FROM sync_conflicts c
         LEFT JOIN staff s ON s.id = c.staff_id
         LEFT JOIN bookings b ON b.id = c.booking_id
         LEFT JOIN customers cu ON cu.id = b.customer_id
         LEFT JOIN staff rv ON rv.id = c.resolved_by_staff_id
         LEFT JOIN device_events de ON de.id = c.device_event_id
         LEFT JOIN staff rb ON rb.id = de.recovered_by_staff_id
        WHERE c.kind = 'recovered_event' AND ($1::boolean OR c.resolved_at IS NULL)
        ORDER BY c.created_at DESC, c.id
        LIMIT 500`,
      [all],
    );
    return rows.map((r) => ({
      id: r.id,
      staffId: r.staff_id,
      staffName: r.staff_name,
      eventId: r.device_event_id,
      type: str(r.details.type),
      bookingId: r.booking_id,
      customerName: r.customer_name,
      occurredAt: str(r.details.occurredAt),
      approximate: r.details.approximate === true,
      suspendedAt: str(r.details.suspendedAt),
      reason: str(r.details.reason),
      recoveredBy: r.recoverer_id ? { id: r.recoverer_id, name: r.recoverer_name } : null,
      recoveredAt: r.created_at.toISOString(),
      reviewedAt: r.resolved_at?.toISOString() ?? null,
      reviewedBy: r.resolved_by_staff_id ? { id: r.resolved_by_staff_id, name: r.reviewer_name } : null,
    }));
  },

  /** Marks one recovered event reviewed (idempotent). False when there is no such item. */
  async acknowledge(t: TenantContext, id: string, managerId: string, ip: string | null): Promise<boolean> {
    return t.db.tx(async (q) => {
      const { rows } = await q.query<{ resolved_at: Date | null; staff_id: string; device_event_id: string | null }>(
        "SELECT resolved_at, staff_id, device_event_id FROM sync_conflicts WHERE id = $1 AND kind = 'recovered_event' FOR UPDATE",
        [id],
      );
      const row = rows[0];
      if (!row) return false;
      if (row.resolved_at) return true;
      await q.query('UPDATE sync_conflicts SET resolved_at = now(), resolved_by_staff_id = $2 WHERE id = $1', [id, managerId]);
      await writeAudit(q, {
        actorKind: 'staff',
        actorId: managerId,
        action: 'staff.recovered_event_reviewed',
        targetKind: 'staff',
        targetId: row.staff_id,
        ip,
        details: { itemId: id, eventId: row.device_event_id },
      });
      return true;
    });
  },
};

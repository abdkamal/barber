import type { TenantQueryable } from '../tenancy/tenant-context';

/**
 * Phone numbers needing the manager's attention (ق20, review H2): two or more walk-in records not
 * linked to any account, or a pending/suspended account holding a number that walk-in records use
 * (a proposed or effective link must not be trusted before the manager looks at it).
 */
export const PHONE_DISPUTES_SQL = `
  SELECT w.phone FROM customers w
   WHERE w.password_hash IS NULL AND NOT EXISTS (SELECT 1 FROM customers a WHERE a.linked_walk_in_id = w.id)
   GROUP BY w.phone HAVING count(*) > 1
  UNION
  SELECT a.phone FROM customers a
   WHERE a.password_hash IS NOT NULL AND a.phone_released_at IS NULL AND a.status IN ('pending', 'suspended')
     AND EXISTS (SELECT 1 FROM customers w WHERE w.phone = a.phone AND w.password_hash IS NULL)`;

export interface DateRange {
  from: string; // 'YYYY-MM-DD', inclusive, matches bookings.work_date (already the salon business day)
  to: string;
}

export interface StaffLabel {
  id: string;
  name: string;
}

export const ReportsRepo = {
  /** Barbers, plus managers who served customers (a manager may also cut hair). */
  async staffList(q: TenantQueryable): Promise<StaffLabel[]> {
    const { rows } = await q.query<StaffLabel>(
      `SELECT id, name FROM staff s
        WHERE s.role = 'barber' OR EXISTS (SELECT 1 FROM bookings b WHERE b.staff_id = s.id AND b.actual_start IS NOT NULL)
        ORDER BY name`,
    );
    return rows;
  },

  /** Confirmed vs awaiting-confirmation revenue, per barber (design §9.1). */
  async revenue(q: TenantQueryable, r: DateRange) {
    const { rows } = await q.query<{
      staff_id: string;
      staff_name: string;
      confirmed_minor: string;
      expected_confirmed_minor: string;
      awaiting_minor: string;
      discrepancies: string;
    }>(
      `SELECT b.staff_id, s.name AS staff_name,
              -- confirmed = what was actually collected (device amount); expected = server price snapshot
              COALESCE(SUM(COALESCE(p.confirmed_amount_minor, p.amount_minor)) FILTER (WHERE p.status = 'confirmed'), 0) AS confirmed_minor,
              COALESCE(SUM(p.amount_minor) FILTER (WHERE p.status = 'confirmed'), 0) AS expected_confirmed_minor,
              COALESCE(SUM(p.amount_minor) FILTER (WHERE p.status = 'awaiting_confirmation'), 0) AS awaiting_minor,
              count(*) FILTER (WHERE p.discrepancy) AS discrepancies
         FROM bookings b
         JOIN staff s ON s.id = b.staff_id
         LEFT JOIN payments p ON p.booking_id = b.id
        WHERE b.work_date BETWEEN $1 AND $2
        GROUP BY b.staff_id, s.name
        ORDER BY s.name`,
      [r.from, r.to],
    );
    return rows.map((x) => ({
      staffId: x.staff_id,
      staffName: x.staff_name,
      confirmed: Number(x.confirmed_minor),
      expectedConfirmed: Number(x.expected_confirmed_minor),
      awaiting: Number(x.awaiting_minor),
      discrepancies: Number(x.discrepancies),
    }));
  },

  /** Visits done / cancellations / no-shows per barber (design §9.2). */
  async visits(q: TenantQueryable, r: DateRange) {
    const { rows } = await q.query<{ staff_id: string; staff_name: string; done: string; cancelled: string; no_show: string }>(
      `SELECT b.staff_id, s.name AS staff_name,
              count(*) FILTER (WHERE b.status = 'done') AS done,
              count(*) FILTER (WHERE b.status = 'cancelled') AS cancelled,
              count(*) FILTER (WHERE b.status = 'no_show') AS no_show
         FROM bookings b
         JOIN staff s ON s.id = b.staff_id
        WHERE b.work_date BETWEEN $1 AND $2
        GROUP BY b.staff_id, s.name
        ORDER BY s.name`,
      [r.from, r.to],
    );
    return rows.map((x) => ({ staffId: x.staff_id, staffName: x.staff_name, done: Number(x.done), cancelled: Number(x.cancelled), noShow: Number(x.no_show) }));
  },

  /** Postponements & skips per barber (ق21/ق22 both write a `postponed` booking_events row). */
  async postponements(q: TenantQueryable, r: DateRange) {
    const { rows } = await q.query<{ staff_id: string; postponements: string }>(
      `SELECT b.staff_id, count(*) AS postponements
         FROM booking_events e
         JOIN bookings b ON b.id = e.booking_id
        WHERE e.type = 'postponed' AND b.work_date BETWEEN $1 AND $2
        GROUP BY b.staff_id`,
      [r.from, r.to],
    );
    return new Map(rows.map((x) => [x.staff_id, Number(x.postponements)]));
  },

  /** Most requested services + revenue, completed bookings only (design §9.3). */
  async topServices(q: TenantQueryable, r: DateRange, limit = 10) {
    const { rows } = await q.query<{ service_id: string; name_snapshot: string; times: string; revenue_minor: string }>(
      // Revenue comes from confirmed payments (what was collected), split across a booking's
      // services in proportion to their price snapshots (equally when all are free).
      `WITH alloc AS (
         SELECT bs.service_id, bs.name_snapshot, p.status AS pay_status,
                COALESCE(p.confirmed_amount_minor, p.amount_minor)::numeric
                  * COALESCE(bs.price_minor::numeric / NULLIF(SUM(bs.price_minor) OVER (PARTITION BY b.id), 0),
                             1.0 / COUNT(*) OVER (PARTITION BY b.id)) AS share
           FROM booking_services bs
           JOIN bookings b ON b.id = bs.booking_id
           LEFT JOIN payments p ON p.booking_id = b.id
          WHERE b.status = 'done' AND b.work_date BETWEEN $1 AND $2
       )
       SELECT service_id, name_snapshot, count(*) AS times,
              COALESCE(SUM(share) FILTER (WHERE pay_status = 'confirmed'), 0) AS revenue_minor
         FROM alloc
        GROUP BY service_id, name_snapshot
        ORDER BY times DESC, revenue_minor DESC
        LIMIT $3`,
      [r.from, r.to, limit],
    );
    return rows.map((x) => ({ serviceId: x.service_id, name: x.name_snapshot, times: Number(x.times), revenue: Math.round(Number(x.revenue_minor)) }));
  },

  /**
   * Average actual duration vs the base duration, per barber per service (design §9.3).
   * A booking's total actual time is split across its services proportionally to their
   * duration snapshot (no per-service start/end is recorded — see final report's assumptions).
   */
  async durationVsBase(q: TenantQueryable, r: DateRange) {
    const { rows } = await q.query<{
      staff_id: string;
      staff_name: string;
      service_id: string;
      name_snapshot: string;
      avg_actual_minutes: string;
      avg_base_minutes: string;
      samples: string;
    }>(
      `WITH svc_alloc AS (
         SELECT b.staff_id, bs.service_id, bs.name_snapshot, bs.duration_minutes_snapshot,
                EXTRACT(EPOCH FROM (b.actual_end - b.actual_start)) / 60.0
                  * (bs.duration_minutes_snapshot::numeric / NULLIF(SUM(bs.duration_minutes_snapshot) OVER (PARTITION BY b.id), 0))
                  AS actual_minutes
           FROM bookings b
           JOIN booking_services bs ON bs.booking_id = b.id
          WHERE b.status = 'done' AND b.work_date BETWEEN $1 AND $2
            AND b.actual_start IS NOT NULL AND b.actual_end IS NOT NULL
            -- approximate / clamped device times (restart offline, implausible clock) are not measurements
            AND NOT EXISTS (SELECT 1 FROM booking_events e WHERE e.booking_id = b.id AND e.approximate_time
                               AND e.type IN ('service_started', 'service_finished'))
            AND NOT EXISTS (SELECT 1 FROM duration_samples d WHERE d.booking_id = b.id AND d.exclusion_reason IN ('approximate_time', 'clamped_time'))
       )
       SELECT sa.staff_id, s.name AS staff_name, sa.service_id, sa.name_snapshot,
              avg(sa.actual_minutes) AS avg_actual_minutes, avg(sa.duration_minutes_snapshot) AS avg_base_minutes, count(*) AS samples
         FROM svc_alloc sa
         JOIN staff s ON s.id = sa.staff_id
        GROUP BY sa.staff_id, s.name, sa.service_id, sa.name_snapshot
        ORDER BY s.name, sa.name_snapshot`,
      [r.from, r.to],
    );
    return rows.map((x) => ({
      staffId: x.staff_id,
      staffName: x.staff_name,
      serviceId: x.service_id,
      name: x.name_snapshot,
      avgActualMinutes: Number(x.avg_actual_minutes),
      avgBaseMinutes: Number(x.avg_base_minutes),
      samples: Number(x.samples),
    }));
  },

  /** Mean absolute + p90 minutes between the original expected start and the actual start (design §9.4). */
  async etaAccuracy(q: TenantQueryable, r: DateRange) {
    const { rows } = await q.query<{ staff_id: string; staff_name: string; mean_abs_minutes: string | null; p90_minutes: string | null; samples: string }>(
      `SELECT b.staff_id, s.name AS staff_name,
              avg(abs(EXTRACT(EPOCH FROM (b.actual_start - b.original_expected_start)))) / 60.0 AS mean_abs_minutes,
              percentile_cont(0.9) WITHIN GROUP (ORDER BY abs(EXTRACT(EPOCH FROM (b.actual_start - b.original_expected_start)))) / 60.0 AS p90_minutes,
              count(*) AS samples
         FROM bookings b
         JOIN staff s ON s.id = b.staff_id
        WHERE b.work_date BETWEEN $1 AND $2 AND b.original_expected_start IS NOT NULL AND b.actual_start IS NOT NULL
        GROUP BY b.staff_id, s.name
        ORDER BY s.name`,
      [r.from, r.to],
    );
    return rows.map((x) => ({
      staffId: x.staff_id,
      staffName: x.staff_name,
      meanAbsMinutes: x.mean_abs_minutes == null ? null : Number(x.mean_abs_minutes),
      p90Minutes: x.p90_minutes == null ? null : Number(x.p90_minutes),
      samples: Number(x.samples),
    }));
  },

  /** Bookings-per-hour-of-day histogram, in the salon's own timezone (design §9.5). Based on actual service start. */
  async peakHours(q: TenantQueryable, r: DateRange, timezone: string) {
    const { rows } = await q.query<{ hour: number; count: string }>(
      `SELECT EXTRACT(HOUR FROM b.actual_start AT TIME ZONE $3)::int AS hour, count(*) AS count
         FROM bookings b
        WHERE b.work_date BETWEEN $1 AND $2 AND b.actual_start IS NOT NULL
        GROUP BY hour
        ORDER BY hour`,
      [r.from, r.to, timezone],
    );
    const byHour = new Map(rows.map((x) => [x.hour, Number(x.count)]));
    return Array.from({ length: 24 }, (_, hour) => ({ hour, count: byHour.get(hour) ?? 0 }));
  },

  /** Pending items (design §9.6) — current state, not tied to the report's date range. */
  async pendingItems(q: TenantQueryable) {
    const [payments, syncConflicts, pendingAccounts, phoneDisputes, discrepancies, unfinished] = await Promise.all([
      q.query<{ n: string }>("SELECT count(*) AS n FROM payments WHERE status = 'awaiting_confirmation'"),
      // Unresolved rows in `sync_conflicts` (migration 002 — bookings/sync module, design §3/§6.2).
      q.query<{ n: string }>('SELECT count(*) AS n FROM sync_conflicts WHERE resolved_at IS NULL'),
      q.query<{ n: string }>("SELECT count(*) AS n FROM customers WHERE status = 'pending' AND password_hash IS NOT NULL"),
      // Same definition as GET /manager/phone-disputes (linked walk-in records are not disputed).
      q.query<{ n: string }>(`SELECT count(*) AS n FROM (${PHONE_DISPUTES_SQL}) d`),
      q.query<{ n: string }>('SELECT count(*) AS n FROM payments WHERE discrepancy'),
      // Round 2 (item 4): services still in progress from a business day that was closed out.
      q.query<{ n: string }>("SELECT count(*) AS n FROM bookings WHERE status = 'in_service' AND day_closed_at IS NOT NULL"),
    ]);
    return {
      unconfirmedPayments: Number(payments.rows[0]!.n),
      syncConflicts: Number(syncConflicts.rows[0]!.n),
      pendingAccounts: Number(pendingAccounts.rows[0]!.n),
      phoneDisputes: Number(phoneDisputes.rows[0]!.n),
      paymentDiscrepancies: Number(discrepancies.rows[0]!.n),
      unfinishedServices: Number(unfinished.rows[0]!.n),
    };
  },
};

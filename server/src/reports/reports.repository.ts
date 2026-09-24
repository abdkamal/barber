import type { TenantQueryable } from '../tenancy/tenant-context';

export interface DateRange {
  from: string; // 'YYYY-MM-DD', inclusive, matches bookings.work_date (already the salon business day)
  to: string;
}

export interface StaffLabel {
  id: string;
  name: string;
}

export const ReportsRepo = {
  async staffList(q: TenantQueryable): Promise<StaffLabel[]> {
    const { rows } = await q.query<StaffLabel>("SELECT id, name FROM staff WHERE role = 'barber' ORDER BY name");
    return rows;
  },

  /** Confirmed vs awaiting-confirmation revenue, per barber (design §9.1). */
  async revenue(q: TenantQueryable, r: DateRange) {
    const { rows } = await q.query<{ staff_id: string; staff_name: string; confirmed_minor: string; awaiting_minor: string }>(
      `SELECT b.staff_id, s.name AS staff_name,
              COALESCE(SUM(p.amount_minor) FILTER (WHERE p.status = 'confirmed'), 0) AS confirmed_minor,
              COALESCE(SUM(p.amount_minor) FILTER (WHERE p.status = 'awaiting_confirmation'), 0) AS awaiting_minor
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
      awaiting: Number(x.awaiting_minor),
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
      `SELECT bs.service_id, bs.name_snapshot, count(*) AS times, SUM(bs.price_minor) AS revenue_minor
         FROM booking_services bs
         JOIN bookings b ON b.id = bs.booking_id
        WHERE b.status = 'done' AND b.work_date BETWEEN $1 AND $2
        GROUP BY bs.service_id, bs.name_snapshot
        ORDER BY times DESC, revenue_minor DESC
        LIMIT $3`,
      [r.from, r.to, limit],
    );
    return rows.map((x) => ({ serviceId: x.service_id, name: x.name_snapshot, times: Number(x.times), revenue: Number(x.revenue_minor) }));
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
    const [payments, syncConflicts, pendingAccounts, phoneDisputes] = await Promise.all([
      q.query<{ n: string }>("SELECT count(*) AS n FROM payments WHERE status = 'awaiting_confirmation'"),
      // Unresolved rows in `sync_conflicts` (migration 002 — bookings/sync module, design §3/§6.2).
      q.query<{ n: string }>('SELECT count(*) AS n FROM sync_conflicts WHERE resolved_at IS NULL'),
      q.query<{ n: string }>("SELECT count(*) AS n FROM customers WHERE status = 'pending' AND password_hash IS NOT NULL"),
      q.query<{ n: string }>(
        `SELECT count(*) AS n FROM (
           SELECT phone FROM customers WHERE password_hash IS NULL
           GROUP BY phone HAVING count(*) > 1
         ) d`,
      ),
    ]);
    return {
      unconfirmedPayments: Number(payments.rows[0]!.n),
      syncConflicts: Number(syncConflicts.rows[0]!.n),
      pendingAccounts: Number(pendingAccounts.rows[0]!.n),
      phoneDisputes: Number(phoneDisputes.rows[0]!.n),
    };
  },
};

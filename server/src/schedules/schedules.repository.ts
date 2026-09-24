import type { TenantQueryable } from '../tenancy/tenant-context';

export interface WorkScheduleRow {
  id: string;
  staff_id: string | null; // null = salon-wide default for that weekday
  weekday: number;
  opens_at: string; // 'HH:MM:SS'
  closes_at: string;
}

export const SchedulesRepo = {
  async list(q: TenantQueryable): Promise<WorkScheduleRow[]> {
    const { rows } = await q.query<WorkScheduleRow>('SELECT * FROM work_schedules ORDER BY staff_id NULLS FIRST, weekday');
    return rows;
  },

  /** Upserts one weekday's hours for a barber (staffId) or the salon default (staffId = null). */
  async upsert(q: TenantQueryable, staffId: string | null, weekday: number, opensAt: string, closesAt: string): Promise<WorkScheduleRow> {
    if (staffId) {
      const { rows } = await q.query<WorkScheduleRow>(
        `INSERT INTO work_schedules (staff_id, weekday, opens_at, closes_at) VALUES ($1, $2, $3, $4)
         ON CONFLICT (staff_id, weekday) WHERE staff_id IS NOT NULL
         DO UPDATE SET opens_at = EXCLUDED.opens_at, closes_at = EXCLUDED.closes_at
         RETURNING *`,
        [staffId, weekday, opensAt, closesAt],
      );
      return rows[0]!;
    }
    const { rows } = await q.query<WorkScheduleRow>(
      `INSERT INTO work_schedules (staff_id, weekday, opens_at, closes_at) VALUES (NULL, $1, $2, $3)
       ON CONFLICT (weekday) WHERE staff_id IS NULL
       DO UPDATE SET opens_at = EXCLUDED.opens_at, closes_at = EXCLUDED.closes_at
       RETURNING *`,
      [weekday, opensAt, closesAt],
    );
    return rows[0]!;
  },

  async deleteOne(q: TenantQueryable, staffId: string | null, weekday: number): Promise<boolean> {
    const { rowCount } = staffId
      ? await q.query('DELETE FROM work_schedules WHERE staff_id = $1 AND weekday = $2', [staffId, weekday])
      : await q.query('DELETE FROM work_schedules WHERE staff_id IS NULL AND weekday = $1', [weekday]);
    return (rowCount ?? 0) > 0;
  },
};

export interface BreakRow {
  id: string;
  staff_id: string;
  work_date: string | null;
  type: 'rest' | 'prayer' | 'emergency' | 'walk_in_only';
  start_time: string | null;
  end_time: string | null;
  starts_at: Date | null;
  ends_at: Date | null;
  created_by_staff_id: string | null;
  created_at: Date;
}

export const BreaksRepo = {
  async listForStaff(q: TenantQueryable, staffId: string): Promise<BreakRow[]> {
    const { rows } = await q.query<BreakRow>('SELECT *, work_date::text AS work_date FROM breaks WHERE staff_id = $1 ORDER BY breaks.work_date NULLS FIRST, start_time, starts_at', [staffId]);
    return rows;
  },

  async list(q: TenantQueryable): Promise<BreakRow[]> {
    const { rows } = await q.query<BreakRow>('SELECT *, work_date::text AS work_date FROM breaks ORDER BY staff_id, breaks.work_date NULLS FIRST, start_time, starts_at');
    return rows;
  },

  async insertRecurring(q: TenantQueryable, staffId: string, type: BreakRow['type'], startTime: string, endTime: string, createdBy: string): Promise<BreakRow> {
    const { rows } = await q.query<BreakRow>(
      `INSERT INTO breaks (staff_id, type, start_time, end_time, created_by_staff_id) VALUES ($1, $2, $3, $4, $5) RETURNING *, work_date::text AS work_date`,
      [staffId, type, startTime, endTime, createdBy],
    );
    return rows[0]!;
  },

  async insertDated(q: TenantQueryable, staffId: string, workDate: string, type: BreakRow['type'], startsAt: string, endsAt: string, createdBy: string): Promise<BreakRow> {
    const { rows } = await q.query<BreakRow>(
      `INSERT INTO breaks (staff_id, work_date, type, starts_at, ends_at, created_by_staff_id) VALUES ($1, $2, $3, $4, $5, $6) RETURNING *, work_date::text AS work_date`,
      [staffId, workDate, type, startsAt, endsAt, createdBy],
    );
    return rows[0]!;
  },

  async findById(q: TenantQueryable, id: string): Promise<BreakRow | null> {
    const { rows } = await q.query<BreakRow>('SELECT *, work_date::text AS work_date FROM breaks WHERE id = $1', [id]);
    return rows[0] ?? null;
  },

  async delete(q: TenantQueryable, id: string): Promise<boolean> {
    const { rowCount } = await q.query('DELETE FROM breaks WHERE id = $1', [id]);
    return (rowCount ?? 0) > 0;
  },
};

export interface AbsenceRow {
  id: string;
  staff_id: string;
  work_date: string;
  reason: string | null;
  recorded_by_staff_id: string | null;
  created_at: Date;
}

export const AbsencesRepo = {
  async list(q: TenantQueryable): Promise<AbsenceRow[]> {
    const { rows } = await q.query<AbsenceRow>('SELECT *, work_date::text AS work_date FROM absences ORDER BY absences.work_date DESC');
    return rows;
  },

  async insert(q: TenantQueryable, staffId: string, workDate: string, reason: string | null, recordedBy: string): Promise<AbsenceRow> {
    const { rows } = await q.query<AbsenceRow>(
      `INSERT INTO absences (staff_id, work_date, reason, recorded_by_staff_id) VALUES ($1, $2, $3, $4)
       ON CONFLICT (staff_id, work_date) DO UPDATE SET reason = EXCLUDED.reason, recorded_by_staff_id = EXCLUDED.recorded_by_staff_id
       RETURNING *, work_date::text AS work_date`,
      [staffId, workDate, reason, recordedBy],
    );
    return rows[0]!;
  },

  async delete(q: TenantQueryable, id: string): Promise<boolean> {
    const { rowCount } = await q.query('DELETE FROM absences WHERE id = $1', [id]);
    return (rowCount ?? 0) > 0;
  },
};

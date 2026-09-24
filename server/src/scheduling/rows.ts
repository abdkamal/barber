import type { TenantQueryable } from '../tenancy/tenant-context';

export type BookingStatus = 'offered' | 'waiting' | 'called' | 'in_service' | 'done' | 'cancelled' | 'no_show' | 'expired';
export const ACTIVE_STATUSES: BookingStatus[] = ['offered', 'waiting', 'called', 'in_service'];

export interface BookingRow {
  id: string;
  customer_id: string;
  staff_id: string;
  kind: 'queue' | 'requested';
  requested_at: Date | null;
  status: BookingStatus;
  queue_position: number | null;
  original_expected_start: Date | null;
  last_shown_expected_start: Date | null;
  postpone_used: boolean;
  actual_start: Date | null;
  actual_end: Date | null;
  source: 'app' | 'barber';
  work_date: string;
  offer_expires_at: Date | null;
  estimated_duration_seconds: number | null;
  service_set_key: string | null;
  projected_start: Date | null;
  projected_end: Date | null;
  last_change_reason: string | null;
  last_change_at: Date | null;
  called_at: Date | null;
  cancelled_at: Date | null;
  cancel_reason: string | null;
  overrun_alerted_at: Date | null;
  serve_late: boolean;
  replaces_booking_id: string | null;
  needs_review: boolean;
  created_at: Date;
  updated_at: Date;
  customer_name: string;
  customer_phone: string;
  customer_is_walk_in: boolean;
}

export const BOOKING_SELECT = `
  SELECT b.id, b.customer_id, b.staff_id, b.kind, b.requested_at, b.status, b.queue_position,
         b.original_expected_start, b.last_shown_expected_start, b.postpone_used, b.actual_start, b.actual_end,
         b.source, b.work_date::text AS work_date, b.offer_expires_at, b.estimated_duration_seconds, b.service_set_key,
         b.projected_start, b.projected_end, b.last_change_reason, b.last_change_at, b.called_at, b.cancelled_at,
         b.cancel_reason, b.overrun_alerted_at, b.serve_late, b.replaces_booking_id, b.needs_review, b.created_at,
         b.updated_at, c.name AS customer_name, c.phone AS customer_phone, (c.password_hash IS NULL) AS customer_is_walk_in
    FROM bookings b JOIN customers c ON c.id = b.customer_id`;

/** Service order within a barber's active queue: in service → called → waiting (by position). */
export const QUEUE_ORDER = `CASE b.status WHEN 'in_service' THEN 0 WHEN 'called' THEN 1 ELSE 2 END, b.queue_position NULLS LAST, b.created_at`;

export interface BookingServiceRow {
  booking_id: string;
  service_id: string;
  name_snapshot: string;
  price_minor: string | number;
  duration_minutes_snapshot: number;
}

export interface ServiceRow {
  id: string;
  name: string;
  base_duration_minutes: number;
  price_minor: string | number;
  active: boolean;
  position: number;
}

export interface StaffInfo {
  id: string;
  name: string;
  role: 'barber' | 'manager';
  active: boolean;
  call_ahead_minutes: number;
  created_at: Date;
}

export interface BarberDayRow {
  id: string;
  staff_id: string;
  work_date: string;
  state: 'not_connected_yet' | 'connected' | 'disconnected' | 'absent';
  first_connected_at: Date | null;
  last_heartbeat_at: Date | null;
  known_work_minutes_at_last_heartbeat: number | null;
  known_work_end_at: Date | null;
  offline_since: Date | null;
  not_connected_alerted_at: Date | null;
  last_device_seq: string | null;
}

export const BARBER_DAY_COLS = `id, staff_id, work_date::text AS work_date, state, first_connected_at, last_heartbeat_at,
  known_work_minutes_at_last_heartbeat, known_work_end_at, offline_since, not_connected_alerted_at, last_device_seq`;

export async function bookingServices(q: TenantQueryable, ids: string[]): Promise<Map<string, BookingServiceRow[]>> {
  const out = new Map<string, BookingServiceRow[]>();
  if (!ids.length) return out;
  const { rows } = await q.query<BookingServiceRow>(
    `SELECT booking_id, service_id, name_snapshot, price_minor, duration_minutes_snapshot
       FROM booking_services WHERE booking_id = ANY($1::uuid[]) ORDER BY position, created_at`,
    [ids],
  );
  for (const r of rows) {
    const list = out.get(r.booking_id) ?? [];
    list.push(r);
    out.set(r.booking_id, list);
  }
  return out;
}

export async function findBooking(q: TenantQueryable, id: string, forUpdate = false): Promise<BookingRow | null> {
  const { rows } = await q.query<BookingRow>(`${BOOKING_SELECT} WHERE b.id = $1${forUpdate ? ' FOR UPDATE OF b' : ''}`, [id]);
  return rows[0] ?? null;
}

export async function staffInfo(q: TenantQueryable, id: string): Promise<StaffInfo | null> {
  const { rows } = await q.query<StaffInfo>(
    'SELECT id, name, role, active, call_ahead_minutes, created_at FROM staff WHERE id = $1',
    [id],
  );
  return rows[0] ?? null;
}

export async function activeServices(q: TenantQueryable): Promise<ServiceRow[]> {
  const { rows } = await q.query<ServiceRow>(
    'SELECT id, name, base_duration_minutes, price_minor, active, position FROM services WHERE active ORDER BY position, name',
  );
  return rows;
}

export async function currentSeq(q: TenantQueryable): Promise<number> {
  const { rows } = await q.query<{ value: string }>('SELECT value FROM change_counter WHERE id = 1');
  return Number(rows[0]?.value ?? 0);
}

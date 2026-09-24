import {
  type BarberDay,
  type BarberDayState,
  type BookingGate,
  bookingGate,
  type Break,
  diffProjections,
  estimateDuration,
  MINUTE,
  type PolicySettings,
  type ProjectedSlot,
  projectQueue,
  type ProjectOptions,
  type QueueEntry,
  serviceSetKey,
} from '@saloni/engine';
import { SettingsRepo, type SettingsRow } from '../settings/settings.repository';
import type { TenantQueryable, TenantSalon } from '../tenancy/tenant-context';
import { type ReasonCode } from './reasons';
import {
  BARBER_DAY_COLS,
  BOOKING_SELECT,
  type BarberDayRow,
  type BookingRow,
  QUEUE_ORDER,
  type StaffInfo,
  staffInfo,
} from './rows';
import { currentShift, dailyBreakInShift, localToUtc, addDays, type ScheduleRow, type Shift, shiftOn } from './time';

/** Heartbeats every 30 s; the barber is considered disconnected after 90 s without one (design §11). */
export const HEARTBEAT_TIMEOUT_MS = 90_000;

/** Bookings are same-day only; anything older than this is a leftover of a past business day. */
export const ACTIVE_BOOKING_MAX_AGE_MS = 26 * 60 * MINUTE;

export function policyFrom(s: SettingsRow): PolicySettings {
  return {
    changeMargin: s.eta_change_notify_minutes * MINUTE,
    maxOfflineWindow: s.max_disconnect_window_minutes * MINUTE,
    gapBufferMin: s.gap_margin_min_minutes * MINUTE,
    gapBufferRatio: s.gap_margin_percent / 100,
    offerHold: s.offer_hold_minutes * MINUTE,
    overrunAlertRatio: s.overrun_alert_percent / 100,
  };
}

/** Collects what must happen after the transaction commits (WS push, notification dispatch). */
export class Effects {
  readonly staff = new Set<string>();
  notifications = false;
}

// ─── Schedules & shifts ──────────────────────────────────────────────────────────────

export async function schedulesOf(q: TenantQueryable, staffId: string): Promise<ScheduleRow[]> {
  const { rows } = await q.query<ScheduleRow>(
    'SELECT weekday, opens_at::text AS opens_at, closes_at::text AS closes_at FROM work_schedules WHERE staff_id = $1',
    [staffId],
  );
  return rows;
}

export async function resolveShift(q: TenantQueryable, tz: string, staffId: string, now: number, lookaheadMs: number): Promise<Shift | null> {
  return currentShift(await schedulesOf(q, staffId), tz, now, lookaheadMs);
}

/** The shift of a known work date (for events arriving late); falls back to the whole local day. */
export async function shiftForDate(q: TenantQueryable, tz: string, staffId: string, date: string): Promise<Shift> {
  const s = shiftOn(date, await schedulesOf(q, staffId), tz);
  return s ?? { workDate: date, workStart: localToUtc(date, '00:00', tz), workEnd: localToUtc(addDays(date, 1), '00:00', tz) };
}

/** Active staff who work (have a schedule on) the current business day — the salon's "barbers" today. */
export async function workingStaff(q: TenantQueryable): Promise<Array<StaffInfo & { schedules: ScheduleRow[] }>> {
  const { rows } = await q.query<StaffInfo & { weekday: number | null; opens_at: string | null; closes_at: string | null }>(
    `SELECT s.id, s.name, s.role, s.active, s.call_ahead_minutes, s.created_at,
            w.weekday, w.opens_at::text AS opens_at, w.closes_at::text AS closes_at
       FROM staff s JOIN work_schedules w ON w.staff_id = s.id
      WHERE s.active
      ORDER BY s.created_at, s.id`,
  );
  const by = new Map<string, StaffInfo & { schedules: ScheduleRow[] }>();
  for (const r of rows) {
    let s = by.get(r.id);
    if (!s) {
      s = { id: r.id, name: r.name, role: r.role, active: r.active, call_ahead_minutes: r.call_ahead_minutes, created_at: r.created_at, schedules: [] };
      by.set(r.id, s);
    }
    if (r.weekday !== null) s.schedules.push({ weekday: r.weekday, opens_at: r.opens_at!, closes_at: r.closes_at! });
  }
  return [...by.values()];
}

// ─── Day context ──────────────────────────────────────────────────────────────────────

export interface DayCtx {
  salon: TenantSalon;
  now: number;
  settings: SettingsRow;
  policy: PolicySettings;
  staff: StaffInfo;
  shift: Shift;
  day: BarberDay;
  rows: BookingRow[];
  byId: Map<string, BookingRow>;
  queue: QueueEntry[];
  dayRow: BarberDayRow | null;
  state: BarberDayState;
  gate: BookingGate;
  opts: ProjectOptions;
  /** Offers found expired while loading. Locked loads keep them in `queue` until releaseExpiredOffers(). */
  expiredOffers: BookingRow[];
}

export function toEntry(r: BookingRow): QueueEntry {
  return {
    bookingId: r.id,
    kind: r.kind,
    requestedAt: r.requested_at ? r.requested_at.getTime() : undefined,
    status: r.status === 'offered' ? 'waiting' : (r.status as QueueEntry['status']),
    estimatedDuration: (r.estimated_duration_seconds ?? 30 * 60) * 1000,
    actualStart: r.actual_start ? r.actual_start.getTime() : undefined,
    walkIn: r.source === 'barber',
    postponeUsed: r.postpone_used,
    offer: r.status === 'offered',
  };
}

export function stateOf(dayRow: BarberDayRow | null, absent: boolean, now: number): BarberDayState {
  if (absent || dayRow?.state === 'absent') return { kind: 'absent' };
  if (!dayRow?.first_connected_at || !dayRow.last_heartbeat_at) return { kind: 'not_connected' };
  const last = dayRow.last_heartbeat_at.getTime();
  if (now - last <= HEARTBEAT_TIMEOUT_MS) return { kind: 'online' };
  return { kind: 'offline', offlineSince: last, knownWorkEnd: dayRow.known_work_end_at?.getTime() ?? last };
}

/** Wire name of the day state (Dart `BarberDayState`). */
export function stateWire(s: BarberDayState): 'not_connected_yet' | 'connected' | 'disconnected' | 'absent_today' {
  switch (s.kind) {
    case 'online':
      return 'connected';
    case 'offline':
      return 'disconnected';
    case 'absent':
      return 'absent_today';
    default:
      return 'not_connected_yet';
  }
}

export function dbStateOf(s: BarberDayState): BarberDayRow['state'] {
  switch (s.kind) {
    case 'online':
      return 'connected';
    case 'offline':
      return 'disconnected';
    case 'absent':
      return 'absent';
    default:
      return 'not_connected_yet';
  }
}

async function loadBreaks(q: TenantQueryable, tz: string, staffId: string, shift: Shift, opensAt: string | null, now: number): Promise<Break[]> {
  const { rows } = await q.query<{
    type: string;
    work_date: string | null;
    start_time: string | null;
    end_time: string | null;
    starts_at: Date | null;
    ends_at: Date | null;
    open: boolean;
  }>(
    `SELECT type, work_date::text AS work_date, start_time::text AS start_time, end_time::text AS end_time, starts_at, ends_at, open
       FROM breaks
      WHERE staff_id = $1
        AND (work_date IS NULL OR (starts_at < $3 AND (ends_at > $2 OR open)))`,
    [staffId, new Date(shift.workStart), new Date(shift.workEnd)],
  );
  const out: Break[] = [];
  for (const b of rows) {
    const kind = b.type === 'walk_in_only' ? 'walk_in_only' : 'break';
    if (b.work_date === null) {
      const iv = dailyBreakInShift(shift, b.start_time!, b.end_time!, tz, opensAt ?? '00:00');
      out.push({ ...iv, kind });
    } else {
      const start = b.starts_at!.getTime();
      let end = b.ends_at!.getTime();
      // An open break (started on the device, not yet ended) lasts at least until now.
      if (b.open && end <= now) end = now + MINUTE;
      out.push({ start, end, kind });
    }
  }
  return out.sort((a, b) => a.start - b.start);
}

/**
 * Loads a barber's day into engine types. With `lock`, the barber_days row is created if needed
 * and locked FOR UPDATE — every queue mutation for this barber/day serialises on it (§5.13).
 */
export async function loadDay(
  q: TenantQueryable,
  salon: TenantSalon,
  staffId: string,
  shift: Shift,
  now: number,
  opts: { lock?: boolean; settings?: SettingsRow; staff?: StaffInfo } = {},
): Promise<DayCtx> {
  if (opts.lock) {
    await q.query('INSERT INTO barber_days (staff_id, work_date) VALUES ($1, $2) ON CONFLICT (staff_id, work_date) DO NOTHING', [
      staffId,
      shift.workDate,
    ]);
  }
  const { rows: dayRows } = await q.query<BarberDayRow>(
    `SELECT ${BARBER_DAY_COLS} FROM barber_days WHERE staff_id = $1 AND work_date = $2${opts.lock ? ' FOR UPDATE' : ''}`,
    [staffId, shift.workDate],
  );
  const dayRow = dayRows[0] ?? null;
  const settings = opts.settings ?? (await SettingsRepo.get(q));
  const staff = opts.staff ?? (await staffInfo(q, staffId));
  if (!staff) throw new Error('staff not found');
  const { rows: abs } = await q.query('SELECT 1 FROM absences WHERE staff_id = $1 AND work_date = $2', [staffId, shift.workDate]);
  const { rows: sched } = await q.query<{ opens_at: string }>(
    `SELECT opens_at::text AS opens_at FROM work_schedules WHERE staff_id = $1 AND weekday = EXTRACT(DOW FROM $2::date)`,
    [staffId, shift.workDate],
  );
  const breaks = await loadBreaks(q, salon.timezone, staffId, shift, sched[0]?.opens_at ?? null, now);
  const { rows } = await q.query<BookingRow>(
    `${BOOKING_SELECT}
      WHERE b.staff_id = $1 AND b.work_date = $2 AND b.status IN ('offered', 'waiting', 'called', 'in_service')
      ORDER BY ${QUEUE_ORDER}`,
    [staffId, shift.workDate],
  );
  const expiredOffers = rows.filter((r) => r.status === 'offered' && r.offer_expires_at && r.offer_expires_at.getTime() <= now);
  // Locked callers persist the expiry themselves (releaseExpiredOffers); read-only views just skip them.
  const live = opts.lock ? rows : rows.filter((r) => !expiredOffers.includes(r));
  const policy = policyFrom(settings);
  const state = stateOf(dayRow, abs.length > 0, now);
  const gate = bookingGate(state, now, policy);
  return {
    salon,
    now,
    settings,
    policy,
    staff,
    shift,
    day: { barberId: staffId, workStart: shift.workStart, workEnd: shift.workEnd, breaks },
    rows: live,
    byId: new Map(live.map((r) => [r.id, r])),
    queue: live.map(toEntry),
    dayRow,
    state,
    gate,
    opts: gate.frozenAt !== undefined ? { frozenAt: gate.frozenAt } : {},
    expiredOffers: opts.lock ? expiredOffers : [],
  };
}

export function project(ctx: DayCtx, queue: readonly QueueEntry[] = ctx.queue): ProjectedSlot[] {
  return projectQueue(ctx.day, queue, ctx.now, ctx.opts);
}

// ─── Writes ───────────────────────────────────────────────────────────────────────────

export interface BookingEventInput {
  id?: string;
  bookingId: string | null;
  type: string;
  payload?: Record<string, unknown>;
  occurredAt: number;
  actorKind: 'staff' | 'customer' | 'system';
  actorId?: string | null;
  deviceId?: string | null;
  deviceSeq?: number | null;
  approximate?: boolean;
  reason?: string | null;
}

export async function insertBookingEvent(q: TenantQueryable, e: BookingEventInput): Promise<void> {
  await q.query(
    `INSERT INTO booking_events (id, booking_id, type, payload, occurred_at, actor_kind, actor_id, device_id, device_seq, approximate_time, reason)
     VALUES (COALESCE($1::uuid, gen_random_uuid()), $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
    [
      e.id ?? null,
      e.bookingId,
      e.type,
      JSON.stringify(e.payload ?? {}),
      new Date(e.occurredAt),
      e.actorKind,
      e.actorId ?? null,
      e.deviceId ?? null,
      e.deviceSeq ?? null,
      e.approximate ?? false,
      e.reason ?? null,
    ],
  );
}

const OPS: Record<string, 'insert' | 'update' | 'delete'> = {
  booking_created: 'insert',
  booking_removed: 'delete',
};

/** Appends to the staff change feed (design §6.3). seq is assigned in commit order by the DB. */
export async function emitChange(
  q: TenantQueryable,
  effects: Effects,
  c: { staffId: string | null; type: string; entity?: string; bookingId?: string | null; data: Record<string, unknown> },
): Promise<void> {
  await q.query(
    'INSERT INTO changes (entity, entity_id, op, staff_id, data, type) VALUES ($1, $2, $3, $4, $5, $6)',
    [c.entity ?? 'booking', c.bookingId ?? null, OPS[c.type] ?? 'update', c.staffId, JSON.stringify(c.data), c.type],
  );
  if (c.staffId) effects.staff.add(c.staffId);
  else effects.staff.add('*');
}

export interface CommitOptions {
  reason: ReasonCode;
  /** Bookings the operation is about — they get their own event, not an "eta_changed" one. */
  primary?: string[];
  effects: Effects;
  actorKind?: 'staff' | 'customer' | 'system';
  actorId?: string | null;
  /** Projection before the change when the day itself changed (breaks); defaults to the old queue. */
  before?: ProjectedSlot[];
}

/**
 * Persists a new queue for the day: positions, statuses, projections; writes an `eta_changed`
 * booking event (with reason) for every other booking whose expected start moved, and one
 * `queue_updated` change for the barber's devices. Returns the new projection.
 */
export async function commitQueue(q: TenantQueryable, ctx: DayCtx, next: QueueEntry[], o: CommitOptions): Promise<ProjectedSlot[]> {
  const before = o.before ?? project(ctx, ctx.queue);
  const after = project(ctx, next);
  const slotOf = new Map(after.map((s) => [s.bookingId, s]));
  for (let i = 0; i < next.length; i++) {
    const e = next[i]!;
    const s = slotOf.get(e.bookingId)!;
    const status = e.offer ? 'offered' : e.status;
    await q.query(
      `UPDATE bookings SET queue_position = $2, status = $3, postpone_used = $4, actual_start = $5,
              estimated_duration_seconds = $6, projected_start = $7, projected_end = $8,
              kind = $9, requested_at = $10, updated_at = now()
        WHERE id = $1`,
      [
        e.bookingId,
        i,
        status,
        !!e.postponeUsed,
        e.actualStart !== undefined ? new Date(e.actualStart) : null,
        Math.round(e.estimatedDuration / 1000),
        new Date(s.start),
        new Date(s.end),
        e.kind,
        e.kind === 'requested' && e.requestedAt !== undefined ? new Date(e.requestedAt) : null,
      ],
    );
  }
  const primary = new Set(o.primary ?? []);
  for (const d of diffProjections(before, after)) {
    if (primary.has(d.bookingId) || Math.abs(d.delta) < MINUTE) continue;
    await insertBookingEvent(q, {
      bookingId: d.bookingId,
      type: 'eta_changed',
      payload: { before: new Date(d.before).toISOString(), after: new Date(d.after).toISOString(), deltaSec: Math.round(d.delta / 1000) },
      occurredAt: ctx.now,
      actorKind: o.actorKind ?? 'system',
      actorId: o.actorId ?? null,
      reason: o.reason,
    });
    await q.query('UPDATE bookings SET last_change_reason = $2, last_change_at = $3 WHERE id = $1', [d.bookingId, o.reason, new Date(ctx.now)]);
  }
  await emitChange(q, o.effects, {
    staffId: ctx.staff.id,
    type: 'queue_updated',
    entity: 'queue',
    data: {
      workDate: ctx.shift.workDate,
      reason: o.reason,
      queue: next.map((e, i) => ({
        bookingId: e.bookingId,
        status: e.offer ? 'offered' : e.status,
        position: i,
        eta: new Date(slotOf.get(e.bookingId)!.start).toISOString(),
        etaEnd: new Date(slotOf.get(e.bookingId)!.end).toISOString(),
      })),
    },
  });
  ctx.queue = next;
  return after;
}

/** Removes offers that expired (every locked mutation and the scheduler call this first). */
export async function releaseExpiredOffers(q: TenantQueryable, ctx: DayCtx, effects: Effects): Promise<number> {
  if (!ctx.expiredOffers.length) return 0;
  const ids = new Set(ctx.expiredOffers.map((r) => r.id));
  await q.query(
    `UPDATE bookings SET status = 'expired', queue_position = NULL, cancel_reason = COALESCE(cancel_reason, 'offer_expired'), updated_at = now()
      WHERE id = ANY($1::uuid[]) AND status = 'offered'`,
    [[...ids]],
  );
  for (const r of ctx.expiredOffers) {
    await insertBookingEvent(q, { bookingId: r.id, type: 'offer_expired', occurredAt: ctx.now, actorKind: 'system', reason: 'offer_expired' });
    await emitChange(q, effects, { staffId: ctx.staff.id, type: 'booking_removed', bookingId: r.id, data: { bookingId: r.id, status: 'expired' } });
  }
  await commitQueue(q, ctx, ctx.queue.filter((e) => !ids.has(e.bookingId)), { reason: 'offer_released', effects });
  ctx.rows = ctx.rows.filter((r) => !ids.has(r.id));
  for (const id of ids) ctx.byId.delete(id);
  ctx.expiredOffers = [];
  return ids.size;
}

// ─── Durations (ق11) ──────────────────────────────────────────────────────────────────

export async function estimateFor(
  q: TenantQueryable,
  staffId: string,
  customerId: string | null,
  serviceIds: string[],
  baseMinutes: number,
): Promise<{ durationMs: number; setKey: string }> {
  const setKey = serviceSetKey(serviceIds);
  const { rows: b } = await q.query<{ d: number }>(
    `SELECT duration_seconds AS d FROM duration_samples
      WHERE staff_id = $1 AND service_set_key = $2 AND NOT excluded ORDER BY recorded_at DESC LIMIT 40`,
    [staffId, setKey],
  );
  const c = customerId
    ? (
        await q.query<{ d: number }>(
          `SELECT duration_seconds AS d FROM duration_samples
            WHERE staff_id = $1 AND service_set_key = $2 AND customer_id = $3 AND NOT excluded ORDER BY recorded_at DESC LIMIT 10`,
          [staffId, setKey, customerId],
        )
      ).rows
    : [];
  const barberSamples = b.map((r) => r.d * 1000).reverse();
  const customerSamples = c.map((r) => r.d * 1000).reverse();
  return { durationMs: estimateDuration(baseMinutes * MINUTE, barberSamples, customerSamples), setKey };
}

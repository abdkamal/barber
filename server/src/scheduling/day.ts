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
import { addDays, currentShift, dailyBreakInShift, localDate, localToUtc, type ScheduleRow, type Shift, shiftOn, weekday } from './time';

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

/**
 * Effective weekly hours: the staff member's own row for a weekday, else the salon-wide default
 * row (staff_id NULL, migration 003) — defaults apply to barbers only; a manager who also serves
 * customers needs his own rows.
 */
const EFFECTIVE_SCHEDULES = `
  SELECT s.id AS staff_id, w.weekday, w.opens_at::text AS opens_at, w.closes_at::text AS closes_at
    FROM staff s
    JOIN work_schedules w
      ON w.staff_id = s.id
      OR (w.staff_id IS NULL AND s.role = 'barber'
          AND NOT EXISTS (SELECT 1 FROM work_schedules o WHERE o.staff_id = s.id AND o.weekday = w.weekday))
   WHERE s.active`;

export async function schedulesOf(q: TenantQueryable, staffId: string): Promise<ScheduleRow[]> {
  const { rows } = await q.query<ScheduleRow>(`${EFFECTIVE_SCHEDULES} AND s.id = $1`, [staffId]);
  return rows;
}

export async function resolveShift(q: TenantQueryable, tz: string, staffId: string, now: number, lookaheadMs: number): Promise<Shift | null> {
  return currentShift(await schedulesOf(q, staffId), tz, now, lookaheadMs);
}

/** Statuses that keep a business day "open" for its barber after closing time (C1). */
export const OPEN_DAY_STATUSES = ['waiting', 'called', 'in_service'] as const;

/** The shift of a work date, or the whole local day when the barber has no schedule that day. */
export function shiftOrDay(schedules: readonly ScheduleRow[], tz: string, date: string): Shift {
  return (
    shiftOn(date, schedules, tz) ?? { workDate: date, workStart: localToUtc(date, '00:00', tz), workEnd: localToUtc(addDays(date, 1), '00:00', tz) }
  );
}

/** Default of the salon setting `day_close_grace_minutes` (6 h). */
export const DEFAULT_DAY_CLOSE_GRACE_MS = 360 * MINUTE;

/** When a barber's business day opens for booking and how long a past one may stay operational. */
export interface DayWindow {
  /** The booking window opens this long before a shift starts (`booking_opens_before_minutes`). */
  lookaheadMs: number;
  /** A past day stays operational at most this long after its shift end (`day_close_grace_minutes`). */
  graceMs: number;
}

export function dayWindow(s: Pick<SettingsRow, 'booking_opens_before_minutes' | 'day_close_grace_minutes'>): DayWindow {
  return {
    lookaheadMs: s.booking_opens_before_minutes * MINUTE,
    graceMs: (s.day_close_grace_minutes ?? DEFAULT_DAY_CLOSE_GRACE_MS / MINUTE) * MINUTE,
  };
}

/** The moment a past business day becomes stale (see isStaleDay). */
export function staleAt(schedules: readonly ScheduleRow[], tz: string, date: string, win: DayWindow): number {
  const own = shiftOrDay(schedules, tz, date);
  const cap = own.workEnd + win.graceMs;
  for (let k = 1; k <= 7; k++) {
    const next = shiftOn(addDays(date, k), schedules, tz);
    if (next && next.workStart > own.workStart) return Math.max(own.workEnd, Math.min(cap, next.workStart - win.lookaheadMs));
  }
  return cap;
}

/**
 * A past business day is "stale" at the EARLIER of: the barber's next business day beginning (its
 * booking window opened — `lookaheadMs` before opening) and the day's own shift end + a bounded grace
 * (`day_close_grace_minutes`, round 2: a salon closed on Fridays or a barber working one day a week
 * must not keep yesterday's queue alive for days). Never before the shift ended. Stale days are
 * closed out by the scheduler (closeStaleDays) and never shown as current.
 */
export function isStaleDay(schedules: readonly ScheduleRow[], tz: string, date: string, now: number, win: DayWindow): boolean {
  const own = shiftOrDay(schedules, tz, date);
  if (now < own.workEnd) return false;
  return now >= staleAt(schedules, tz, date, win);
}

/**
 * The barber's operational day (C1): the running shift; otherwise the most recent ended shift that
 * still has active bookings (served after closing — ق24 — or an unfinished service) and is not stale;
 * otherwise the shift whose booking window is open. New bookings and walk-ins still use the current
 * shift only (`resolveShift`), so nothing new is accepted after closing.
 */
export async function operationalShift(
  q: TenantQueryable,
  tz: string,
  staffId: string,
  now: number,
  win: DayWindow,
  schedules?: readonly ScheduleRow[],
): Promise<Shift | null> {
  const sch = schedules ?? (await schedulesOf(q, staffId));
  const cur = currentShift(sch, tz, now, win.lookaheadMs);
  if (cur && now >= cur.workStart) return cur;
  const { rows } = await q.query<{ work_date: string }>(
    `SELECT DISTINCT work_date::text AS work_date FROM bookings
      WHERE staff_id = $1 AND status = ANY($2::text[]) AND day_closed_at IS NULL AND work_date <= $3::date
      ORDER BY work_date DESC LIMIT 3`,
    [staffId, OPEN_DAY_STATUSES, cur?.workDate ?? localDate(now, tz)],
  );
  for (const r of rows) {
    if (cur && r.work_date === cur.workDate) continue;
    const s = shiftOrDay(sch, tz, r.work_date);
    if (s.workEnd <= now && !isStaleDay(sch, tz, r.work_date, now, win)) return s;
  }
  return cur;
}

/** Opening time (local) of a staff member's shift on a date — anchors recurring breaks (ق30). */
export async function opensAtOn(q: TenantQueryable, staffId: string, date: string): Promise<string | null> {
  const wd = weekday(date);
  return (await schedulesOf(q, staffId)).find((r) => r.weekday === wd)?.opens_at ?? null;
}

/** The shift of a known work date (for events arriving late); falls back to the whole local day. */
export async function shiftForDate(q: TenantQueryable, tz: string, staffId: string, date: string): Promise<Shift> {
  return shiftOrDay(await schedulesOf(q, staffId), tz, date);
}

/** Active staff who work (have a schedule on) the current business day — the salon's "barbers" today. */
export async function workingStaff(q: TenantQueryable): Promise<Array<StaffInfo & { schedules: ScheduleRow[] }>> {
  const { rows: staff } = await q.query<StaffInfo>(
    'SELECT id, name, role, active, call_ahead_minutes, created_at FROM staff WHERE active ORDER BY created_at, id',
  );
  const { rows } = await q.query<ScheduleRow & { staff_id: string }>(EFFECTIVE_SCHEDULES);
  const by = new Map<string, ScheduleRow[]>();
  for (const r of rows) {
    const list = by.get(r.staff_id) ?? [];
    list.push({ weekday: r.weekday, opens_at: r.opens_at, closes_at: r.closes_at });
    by.set(r.staff_id, list);
  }
  return staff.filter((s) => by.has(s.id)).map((s) => ({ ...s, schedules: by.get(s.id)! }));
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
  // ق26: an absences row (reported by the barber or the manager) is the source of truth.
  if (absent) return { kind: 'absent' };
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
 * Creates (if needed) and locks a barber-day row FOR UPDATE — the per-barber lock every queue
 * mutation serialises on (§5.13). Lock order everywhere: barber-day row(s) → breaks rows →
 * change_counter (the first emitted change). Re-locking in the same transaction is a no-op.
 */
export async function lockDayRow(q: TenantQueryable, staffId: string, workDate: string): Promise<void> {
  await q.query('INSERT INTO barber_days (staff_id, work_date) VALUES ($1, $2) ON CONFLICT (staff_id, work_date) DO NOTHING', [staffId, workDate]);
  await q.query('SELECT 1 FROM barber_days WHERE staff_id = $1 AND work_date = $2 FOR UPDATE', [staffId, workDate]);
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
  const breaks = await loadBreaks(q, salon.timezone, staffId, shift, await opensAtOn(q, staffId, shift.workDate), now);
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

/**
 * Locks several barber days in one consistent order (staff id, then work date) and only then
 * releases their expired offers — no change is emitted (the change counter row is locked by the
 * first emitted change) before every day lock is held, so concurrent operations cannot deadlock.
 * Keys of the result: `${staffId}|${workDate}`.
 */
export async function lockDays(
  q: TenantQueryable,
  salon: TenantSalon,
  specs: Array<{ staffId: string; shift: Shift; staff?: StaffInfo }>,
  now: number,
  settings: SettingsRow,
  effects: Effects,
): Promise<Map<string, DayCtx>> {
  const unique = new Map<string, (typeof specs)[number]>();
  for (const s of specs) {
    const k = `${s.staffId}|${s.shift.workDate}`;
    if (!unique.has(k) || (s.staff && !unique.get(k)!.staff)) unique.set(k, s);
  }
  const ordered = [...unique.entries()].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  const out = new Map<string, DayCtx>();
  for (const [k, s] of ordered) {
    out.set(k, await loadDay(q, salon, s.staffId, s.shift, now, { lock: true, settings, ...(s.staff ? { staff: s.staff } : {}) }));
  }
  for (const ctx of out.values()) await releaseExpiredOffers(q, ctx, effects);
  return out;
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

// ─── ق5 reference / ق23 (server-known facts only) ─────────────────────────────────────

/**
 * Records a new time the SERVER told the customer (call, ق5 notice, postponement, transfer…).
 * It becomes his ق5 reference (`last_shown_expected_start`) and his server-issued reference
 * (`told_expected_start`). When the system moves him earlier than the last SERVER-issued time,
 * that time is kept in `reference_before_advance` — the ق23 exemption is judged against it
 * (review I1/H1). Neither is ever derived from `last_shown_expected_start`, which the customer's
 * app may also set ("seen", ق5 only), so client input can never widen the ق23 exemption.
 * `reset` forgets the pre-advance reference (a postponement, a transfer or the customer's own
 * change gives him a new known time).
 */
export async function updateReference(q: TenantQueryable, id: string, at: number, opts: { reset?: boolean } = {}): Promise<void> {
  await q.query(
    `UPDATE bookings SET
        reference_before_advance = CASE
          WHEN $3 THEN NULL
          WHEN $2 < COALESCE(told_expected_start, original_expected_start) - interval '1 minute'
            THEN COALESCE(reference_before_advance, told_expected_start, original_expected_start)
          WHEN reference_before_advance IS NOT NULL AND $2 >= reference_before_advance THEN NULL
          ELSE reference_before_advance END,
        told_expected_start = $2,
        last_shown_expected_start = $2
      WHERE id = $1`,
    [id, new Date(at), !!opts.reset],
  );
}

/** ق23: the time the customer is known (by the server) to have expected before any system advance — never client input. */
export function exemptionReference(r: BookingRow): number | undefined {
  return (r.reference_before_advance ?? r.told_expected_start ?? r.original_expected_start)?.getTime();
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

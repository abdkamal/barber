import { HttpStatus, Injectable } from '@nestjs/common';
import {
  baseDurationSuspect,
  canMarkNoShow,
  changeDuration,
  finishService,
  insertAt,
  measuredDuration,
  MINUTE,
  postpone,
  postponeIsExempt,
  type QueueEntry,
  remove,
  startService,
} from '@saloni/engine';
import { z } from 'zod';
import type { Principal } from '../auth/principal';
import { ApiError } from '../common/errors';
import { isUniqueViolation } from '../db/sql';
import { NotificationService } from '../notifications/notification.service';
import { Texts } from '../notifications/texts';
import { writeAudit } from '../security/audit';
import { SettingsRepo } from '../settings/settings.repository';
import type { TenantContext, TenantQueryable } from '../tenancy/tenant-context';
import { emitBooking, loadBooking, replaceBookingServices, resolveServices, sumMinutes, sumPrice } from '../scheduling/booking-writer';
import { nextCall, recordCall } from '../scheduling/calling';
import { Clock } from '../scheduling/clock';
import {
  commitQueue,
  type DayCtx,
  type Effects,
  emitChange,
  estimateFor,
  exemptionReference,
  insertBookingEvent,
  loadDay,
  lockDayRow,
  operationalShift,
  dayWindow,
  project,
  releaseExpiredOffers,
  resolveShift,
  shiftForDate,
  stateWire,
  toEntry,
  updateReference,
} from '../scheduling/day';
import { closeStaleOpenBreaks, resolveUnfinishedConflict } from '../scheduling/day-close';
import { PostCommit } from '../scheduling/post-commit';
import type { ReasonCode } from '../scheduling/reasons';
import { type BookingRow, currentSeq } from '../scheduling/rows';
import type { Shift } from '../scheduling/time';

export interface DeviceEventIn {
  id: string;
  deviceSeq: number;
  type: string;
  bookingId?: string | null;
  occurredAt: string;
  approximate?: boolean;
  payload?: Record<string, unknown>;
}

export interface EventOutcome {
  eventId: string;
  result: 'applied' | 'duplicate' | 'rejected';
  reason?: string;
}

export interface ApplyOpts {
  /** Design §6.5 (service level): events after this instant are refused, earlier ones flagged. */
  revokedAt?: number;
  /**
   * ق40: a manager uploads the pending events of a SUSPENDED account from its device. Only events
   * strictly before `suspendedAt` are applied (flagged, marked with the manager, listed for review).
   */
  recovery?: { by: string; suspendedAt: number };
}

/** ق40: per-event result of a manager recovery upload. */
export type RecoveryResult = 'applied' | 'duplicate' | 'rejected_after_suspension' | 'rejected_invalid';

export interface RecoveryOutcome {
  eventId: string;
  result: RecoveryResult;
  reason?: string;
}

export interface RecoveryResponse {
  staffId: string;
  suspendedAt: string;
  results: RecoveryOutcome[];
  summary: { applied: number; duplicate: number; rejectedAfterSuspension: number; rejectedInvalid: number };
}

/** ق40: reason of an event whose device time is not before the suspension. */
export const AFTER_SUSPENSION = 'AFTER_SUSPENSION';

/** A transition the state machine refuses (recorded for the manager, design §6.2). */
class Reject extends Error {
  constructor(
    readonly code: string,
    readonly flag = false,
  ) {
    super(code);
  }
}

interface Applied {
  flagged?: boolean;
  reason?: string;
}

interface EvCtx {
  t: TenantContext;
  me: Principal;
  ev: DeviceEventIn;
  at: number;
  approximate: boolean;
  /** L1: the device time was outside the plausible range and was clamped (sample excluded). */
  clamped: boolean;
  deviceId: string;
  now: number;
  flagged: boolean;
  batch: BatchState;
  /** ق40: the manager recovering this event for a suspended account (null = normal sync). */
  recoveredBy: string | null;
}

/** Per-batch bookkeeping: conflict rows for the manager are capped per batch (review M4). */
interface BatchState {
  conflicts: number;
  suppressed: number;
}

/** At most this many `sync_conflicts` rows per batch; the rest are counted in one summary row. */
export const MAX_CONFLICTS_PER_BATCH = 10;

const Steps = z.object({ steps: z.number().int().min(1).max(50).default(1) }).passthrough();
const ServicesPayload = z.object({ serviceIds: z.array(z.string().uuid()).min(1).max(10) }).passthrough();
const PaymentPayload = z.object({ amount: z.number().int().min(0).max(100_000_000).optional() }).passthrough();
const ClosingPayload = z.object({ decision: z.enum(['serve_late', 'cancel']), reason: z.string().max(300).optional() }).passthrough();
const BreakPayload = z
  .object({ kind: z.enum(['rest', 'prayer', 'emergency']), durationMin: z.number().int().min(1).max(240).optional() })
  .passthrough();
const AbsentPayload = z.object({ reason: z.string().max(300).optional() }).passthrough();

/** Known device event types and their payload schemas (validated before any DB work — review M4). */
const EVENT_TYPES: Record<string, { payload?: z.ZodTypeAny; booking: boolean }> = {
  service_started: { booking: true },
  service_finished: { booking: true },
  services_changed: { payload: ServicesPayload, booking: true },
  payment_confirmed: { payload: PaymentPayload, booking: true },
  postponed: { payload: Steps, booking: true },
  waited: { booking: true },
  no_show: { booking: true },
  closing_decision: { payload: ClosingPayload, booking: true },
  break_started: { payload: BreakPayload, booking: false },
  break_ended: { booking: false },
  absent_today: { payload: AbsentPayload, booking: false },
};

/** Why an event is junk before touching the database (null = well-formed). */
export function precheckEvent(ev: DeviceEventIn): string | null {
  const spec = EVENT_TYPES[ev.type];
  if (!spec) return 'UNKNOWN_EVENT_TYPE';
  if (!Number.isFinite(Date.parse(ev.occurredAt))) return 'INVALID_TIME';
  if (spec.booking && !isUuid(ev.bookingId)) return 'BOOKING_REQUIRED';
  if (spec.payload && !spec.payload.safeParse(ev.payload ?? {}).success) return 'INVALID_PAYLOAD';
  return null;
}

const MAX_FUTURE_SKEW_MS = 2 * MINUTE;
const MAX_EVENT_AGE_MS = 48 * 60 * MINUTE;
const DEFAULT_BREAK_MIN = 15;

/**
 * Applies device events (design §6.2): in deviceSeq order, once per event id, each through the
 * booking state machine (§3) in its own transaction on the barber-day lock. `occurredAt` is the
 * real time of the action; approximate times never feed duration learning.
 */
@Injectable()
export class SyncService {
  constructor(
    private readonly clock: Clock,
    private readonly post: PostCommit,
    private readonly notifications: NotificationService,
  ) {}

  async applyBatch(t: TenantContext, me: Principal, events: DeviceEventIn[], opts: ApplyOpts = {}): Promise<EventOutcome[]> {
    const sorted = [...events].sort((a, b) => a.deviceSeq - b.deviceSeq);
    const out = new Map<string, EventOutcome>();
    const batch: BatchState = { conflicts: 0, suppressed: 0 };
    // Review M4: malformed events are rejected before any per-event DB work — recorded in one
    // statement (so retries are recognised as duplicates) and summarised in ONE conflict row.
    const ids = [...new Set(events.map((e) => e.id))];
    const { rows: known } = await t.db.query<{ id: string; result: string }>('SELECT id, result FROM device_events WHERE id = ANY($1::uuid[])', [ids]);
    const seen = new Map(known.map((r) => [r.id, r.result]));
    const junk: Array<{ ev: DeviceEventIn; reason: string }> = [];
    for (const ev of sorted) {
      if (seen.has(ev.id)) {
        out.set(ev.id, { eventId: ev.id, result: 'duplicate', reason: seen.get(ev.id)! });
        continue;
      }
      const reason = precheckEvent(ev);
      if (reason) {
        junk.push({ ev, reason });
        out.set(ev.id, { eventId: ev.id, result: 'rejected', reason });
        seen.set(ev.id, 'rejected');
      }
    }
    if (junk.length) await this.recordJunk(t, me, junk, opts.recovery?.by ?? null);
    for (const ev of sorted) if (!out.has(ev.id)) out.set(ev.id, await this.applyOne(t, me, ev, opts, batch));
    if (batch.suppressed) {
      await t.db.query('INSERT INTO sync_conflicts (staff_id, kind, details) VALUES ($1, $2, $3)', [
        me.subjectId,
        'rejected_events_summary',
        JSON.stringify({ count: batch.suppressed }),
      ]);
    }
    // Results in the order the device sent them.
    return events.map((e) => out.get(e.id)!);
  }

  private async recordJunk(t: TenantContext, me: Principal, junk: Array<{ ev: DeviceEventIn; reason: string }>, recoveredBy: string | null): Promise<void> {
    await t.db.tx(async (q) => {
      await q.query(
        `INSERT INTO device_events (id, staff_id, device_id, device_seq, type, booking_id, payload, occurred_at, approximate, result, reason, flagged, recovered_by_staff_id)
         SELECT x.id, $1, $2, x.seq, x.type, x.booking_id, '{}'::jsonb, $3, false, 'rejected', x.reason, true, $9
           FROM unnest($4::uuid[], $5::bigint[], $6::text[], $7::uuid[], $8::text[]) AS x(id, seq, type, booking_id, reason)
         ON CONFLICT (id) DO NOTHING`,
        [
          me.subjectId,
          me.sessionId,
          new Date(this.clock.now()),
          junk.map((j) => j.ev.id),
          junk.map((j) => j.ev.deviceSeq),
          junk.map((j) => String(j.ev.type).slice(0, 40)),
          junk.map((j) => (isUuid(j.ev.bookingId) ? j.ev.bookingId : null)),
          junk.map((j) => j.reason),
          recoveredBy,
        ],
      );
      await q.query('INSERT INTO sync_conflicts (staff_id, kind, details) VALUES ($1, $2, $3)', [
        me.subjectId,
        'rejected_events',
        JSON.stringify({ count: junk.length, samples: junk.slice(0, 5).map((j) => ({ eventId: j.ev.id, type: String(j.ev.type).slice(0, 40), reason: j.reason })) }),
      ]);
    });
  }

  private async applyOne(t: TenantContext, me: Principal, ev: DeviceEventIn, opts: ApplyOpts, batch: BatchState = { conflicts: 0, suppressed: 0 }): Promise<EventOutcome> {
    const prior = await t.db.query<{ result: string; reason: string | null }>('SELECT result, reason FROM device_events WHERE id = $1', [ev.id]);
    if (prior.rows[0]) return { eventId: ev.id, result: 'duplicate', reason: prior.rows[0].result };
    const now = this.clock.now();
    let at = Date.parse(ev.occurredAt);
    let approximate = !!ev.approximate;
    const recovery = opts.recovery;
    const c: EvCtx = { t, me, ev, at, approximate, clamped: false, deviceId: me.sessionId, now, flagged: false, batch, recoveredBy: recovery?.by ?? null };
    try {
      if (!Number.isFinite(at)) throw new Reject('INVALID_TIME');
      if (at > now + MAX_FUTURE_SKEW_MS) {
        // L1: never in the future beyond a small skew — clamped to now, its duration sample excluded.
        at = now;
        approximate = true;
        c.clamped = true;
      }
      if (recovery) {
        // ق40: strictly before the suspension; applied, flagged and listed for manager review.
        const refused = recoveryTimeCheck(at, recovery.suspendedAt, now);
        if (refused) throw new Reject(refused);
        c.flagged = true;
      } else if (at < now - MAX_EVENT_AGE_MS) {
        throw new Reject('EVENT_TOO_OLD');
      } else if (opts.revokedAt !== undefined) {
        // Design §6.5: events before the account was stopped are accepted and flagged; later ones are refused.
        if (at > opts.revokedAt) throw new Reject('ACCOUNT_REVOKED', true);
        c.flagged = true;
      }
      c.at = at;
      c.approximate = approximate;
      const applied = await this.post.tx(t, async (q, effects) => {
        const r = await this.dispatch(q, effects, c);
        // ق40: an L1 clamp (e.g. never before the booking existed) must not carry a recovered
        // event past the suspension — the whole transaction is rolled back and it is refused.
        if (recovery && c.at >= recovery.suspendedAt) throw new Reject(AFTER_SUSPENSION);
        await q.query(
          `INSERT INTO device_events (id, staff_id, device_id, device_seq, type, booking_id, payload, occurred_at, approximate, result, reason, flagged, recovered_by_staff_id)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'applied', $10, $11, $12)`,
          [ev.id, me.subjectId, c.deviceId, ev.deviceSeq, ev.type, ev.bookingId ?? null, JSON.stringify(ev.payload ?? {}), new Date(c.at), c.approximate, r.reason ?? null, !!(r.flagged || c.flagged), c.recoveredBy],
        );
        if (recovery) {
          // ق40: every recovered event waits for the manager's acknowledgement (review list).
          await q.query('INSERT INTO sync_conflicts (staff_id, booking_id, device_event_id, kind, details) VALUES ($1, $2, $3, $4, $5)', [
            me.subjectId,
            ev.bookingId && (await loadBooking(q, ev.bookingId)) ? ev.bookingId : null,
            ev.id,
            'recovered_event',
            JSON.stringify({
              type: ev.type,
              occurredAt: new Date(c.at).toISOString(),
              approximate: c.approximate,
              suspendedAt: new Date(recovery.suspendedAt).toISOString(),
              recoveredBy: recovery.by,
              ...(r.reason ? { reason: r.reason } : {}),
            }),
          ]);
        } else if (c.flagged && !r.flagged) {
          await q.query('INSERT INTO sync_conflicts (staff_id, booking_id, device_event_id, kind, details) VALUES ($1, $2, $3, $4, $5)', [
            me.subjectId,
            ev.bookingId ?? null,
            ev.id,
            'event_from_revoked_account',
            JSON.stringify({ type: ev.type, occurredAt: new Date(c.at).toISOString(), revokedAt: opts.revokedAt ? new Date(opts.revokedAt).toISOString() : null }),
          ]);
        }
        return r;
      });
      return { eventId: ev.id, result: 'applied', ...(applied.reason ? { reason: applied.reason } : {}) };
    } catch (e) {
      if (isUniqueViolation(e)) return { eventId: ev.id, result: 'duplicate' };
      const code = e instanceof Reject ? e.code : e instanceof ApiError ? e.code : e instanceof z.ZodError ? 'INVALID_PAYLOAD' : null;
      if (!code) throw e;
      // ق40: the manager recovering the events sees every rejection in the answer — no push alert.
      await this.recordRejection(t, me, c, code, e instanceof Reject && e.flag && !c.recoveredBy);
      return { eventId: ev.id, result: 'rejected', reason: code };
    }
  }

  private async recordRejection(t: TenantContext, me: Principal, c: EvCtx, code: string, notifyManagers: boolean): Promise<void> {
    await this.post.tx(t, async (q, effects) => {
      const ins = await q.query(
        `INSERT INTO device_events (id, staff_id, device_id, device_seq, type, booking_id, payload, occurred_at, approximate, result, reason, flagged, recovered_by_staff_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'rejected', $10, true, $11) ON CONFLICT (id) DO NOTHING`,
        [
          c.ev.id,
          me.subjectId,
          c.deviceId,
          c.ev.deviceSeq,
          String(c.ev.type).slice(0, 40),
          isUuid(c.ev.bookingId) ? c.ev.bookingId : null,
          JSON.stringify(c.ev.payload ?? {}),
          new Date(Number.isFinite(c.at) ? c.at : c.now),
          c.approximate,
          code,
          c.recoveredBy,
        ],
      );
      if (!ins.rowCount) return;
      // ق40: an event after the suspension is simply not applied (reported to the manager uploading it).
      if (c.recoveredBy && code === AFTER_SUSPENSION) return;
      if (c.batch.conflicts >= MAX_CONFLICTS_PER_BATCH) {
        c.batch.suppressed++;
        return;
      }
      c.batch.conflicts++;
      const bookingId = isUuid(c.ev.bookingId) && (await loadBooking(q, c.ev.bookingId!)) ? c.ev.bookingId! : null;
      await q.query('INSERT INTO sync_conflicts (staff_id, booking_id, device_event_id, kind, details) VALUES ($1, $2, $3, $4, $5)', [
        me.subjectId,
        bookingId,
        c.ev.id,
        'rejected_event',
        JSON.stringify({ type: c.ev.type, reason: code }),
      ]);
      if (notifyManagers) await this.alertManagers(q, effects, me, bookingId, `رُفض حدث «${c.ev.type}» (${code})`);
    });
  }

  private async alertManagers(q: TenantQueryable, effects: Effects, me: Principal, bookingId: string | null, what: string): Promise<void> {
    const { rows: s } = await q.query<{ name: string }>('SELECT name FROM staff WHERE id = $1', [me.subjectId]);
    const b = bookingId ? await loadBooking(q, bookingId) : null;
    await this.notifications.toManagers(q, effects, {
      type: 'sync_conflict',
      bookingId,
      text: Texts.syncConflict(s[0]?.name ?? '', b?.customer_name ?? '—', what),
    });
  }

  // ─── State machine ──────────────────────────────────────────────────────────────────

  private dispatch(q: TenantQueryable, effects: Effects, c: EvCtx): Promise<Applied> {
    switch (c.ev.type) {
      case 'service_started':
        return this.started(q, effects, c);
      case 'service_finished':
        return this.finished(q, effects, c);
      case 'services_changed':
        return this.servicesChanged(q, effects, c);
      case 'payment_confirmed':
        return this.paymentConfirmed(q, effects, c);
      case 'postponed':
        return this.postponed(q, effects, c);
      case 'waited':
        return this.waited(q, effects, c);
      case 'no_show':
        return this.noShow(q, effects, c);
      case 'closing_decision':
        return this.closingDecision(q, effects, c);
      case 'break_started':
        return this.breakStarted(q, effects, c);
      case 'break_ended':
        return this.breakEnded(q, effects, c);
      case 'absent_today':
        return this.absent(q, effects, c);
      default:
        throw new Reject('UNKNOWN_EVENT_TYPE');
    }
  }

  /** The event's booking — only the barber's own (managers may also confirm any payment). */
  private async booking(q: TenantQueryable, c: EvCtx, managerMayActOnAny = false): Promise<BookingRow> {
    if (!isUuid(c.ev.bookingId)) throw new Reject('BOOKING_REQUIRED');
    const row = await loadBooking(q, c.ev.bookingId!);
    if (!row) throw new Reject('BOOKING_NOT_FOUND');
    if (row.staff_id !== c.me.subjectId && !(managerMayActOnAny && c.me.role === 'manager')) throw new Reject('NOT_YOUR_BOOKING');
    return row;
  }

  private async lockDay(q: TenantQueryable, c: EvCtx, row: BookingRow, effects: Effects): Promise<DayCtx> {
    const shift = await shiftForDate(q, c.t.salon.timezone, row.staff_id, row.work_date);
    const ctx = await loadDay(q, c.t.salon, row.staff_id, shift, c.now, { lock: true });
    await releaseExpiredOffers(q, ctx, effects);
    return ctx;
  }

  /**
   * Locks the barber's current day. `beforeEmit` runs right after the day lock and before anything
   * is emitted (expired offers are released after it) — the place to lock `breaks` rows, so the
   * lock order is always barber-day row → breaks rows → change_counter (round 2, item 3).
   */
  private async lockToday(q: TenantQueryable, c: EvCtx, effects: Effects, beforeEmit?: (shift: Shift) => Promise<void>): Promise<DayCtx> {
    const settings = await SettingsRepo.get(q);
    const lookahead = settings.booking_opens_before_minutes * MINUTE;
    const shift =
      (await resolveShift(q, c.t.salon.timezone, c.me.subjectId, c.at, lookahead)) ??
      (await operationalShift(q, c.t.salon.timezone, c.me.subjectId, c.now, dayWindow(settings)));
    if (!shift) throw new Reject('NOT_WORKING');
    await lockDayRow(q, c.me.subjectId, shift.workDate);
    if (beforeEmit) await beforeEmit(shift);
    const ctx = await loadDay(q, c.t.salon, c.me.subjectId, shift, c.now, { lock: true, settings });
    await releaseExpiredOffers(q, ctx, effects);
    return ctx;
  }

  private event(q: TenantQueryable, c: EvCtx, bookingId: string | null, type: string, payload: Record<string, unknown> = {}, reason: string | null = null) {
    return insertBookingEvent(q, {
      id: c.ev.id,
      bookingId,
      type,
      payload,
      occurredAt: c.at,
      actorKind: 'staff',
      actorId: c.me.subjectId,
      deviceId: c.deviceId,
      deviceSeq: c.ev.deviceSeq,
      approximate: c.approximate,
      reason,
      recoveredBy: c.recoveredBy,
    });
  }

  /** L1: moves an implausible device time into range; the event becomes approximate (never learned from). */
  private clamp(c: EvCtx, at: number): void {
    c.at = at;
    c.approximate = true;
    c.clamped = true;
  }

  private async commit(q: TenantQueryable, ctx: DayCtx, next: QueueEntry[], reason: ReasonCode, primary: string[], effects: Effects, c: EvCtx) {
    return commitQueue(q, ctx, next, { reason, primary, effects, actorKind: 'staff', actorId: c.me.subjectId });
  }

  /** Notifies a postponed customer and makes the new time his ق5 reference. */
  private async notifyPostponed(q: TenantQueryable, ctx: DayCtx, effects: Effects, id: string, steps: number): Promise<void> {
    const row = ctx.byId.get(id)!;
    const slot = project(ctx).find((s) => s.bookingId === id);
    if (!slot) return;
    await updateReference(q, id, slot.start, { reset: true });
    await this.notifications.toCustomer(q, effects, row.customer_id, {
      type: 'postponed',
      bookingId: id,
      text: Texts.postponed(steps, slot.start, ctx.salon.timezone),
    });
  }

  /** Calls the next customer at once if nobody is called (ق21: immediately after a postponement). */
  private async callImmediately(q: TenantQueryable, ctx: DayCtx, effects: Effects, c: EvCtx): Promise<void> {
    const { queue, calledId } = nextCall(ctx, ctx.queue, true);
    if (!calledId) return;
    await this.commit(q, ctx, queue, 'queue_moved', [calledId], effects, c);
    await recordCall(q, ctx, this.notifications, effects, calledId, true);
  }

  private async started(q: TenantQueryable, effects: Effects, c: EvCtx): Promise<Applied> {
    const row = await this.booking(q, c);
    if (row.status === 'in_service' || row.status === 'done') throw new Reject('ALREADY_STARTED');
    if (row.status === 'offered' || row.status === 'expired') throw new Reject('NOT_CONFIRMED');
    const ctx = await this.lockDay(q, c, row, effects);
    // L1: a service cannot start before its booking existed (server time of creation).
    const { rows: born } = await q.query<{ at: Date | null }>('SELECT min(occurred_at) AS at FROM booking_events WHERE booking_id = $1', [row.id]);
    const createdAt = born[0]?.at?.getTime();
    if (createdAt !== undefined && c.at < createdAt) this.clamp(c, createdAt);
    let queue = ctx.queue;
    let conflict: string | null = null;
    if (row.status === 'cancelled' || row.status === 'no_show') {
      // Design §3: the actual event wins — the customer was served; the manager reviews the conflict.
      conflict = row.status;
      const entry: QueueEntry = { ...toEntry(row), status: 'waiting', offer: false };
      queue = insertAt(queue, queue.filter((e) => e.status !== 'waiting').length, entry);
      await q.query('UPDATE bookings SET cancelled_at = NULL, needs_review = true WHERE id = $1', [row.id]);
      if (row.status === 'no_show') {
        await q.query('UPDATE customers SET no_show_count = GREATEST(0, no_show_count - 1), updated_at = now() WHERE id = $1', [row.customer_id]);
      }
      ctx.byId.set(row.id, row);
    }
    const current = queue.find((e) => e.status === 'in_service');
    if (current && current.bookingId !== row.id) throw new Reject('ANOTHER_IN_SERVICE', true);
    const before = project(ctx, queue);
    const { queue: started, skipped } = startService(queue, row.id, c.at);
    let next = started;
    if (skipped) {
      // ق22: skipping the called customer counts as his postponement — unless ق23 exempts him.
      const s = ctx.byId.get(skipped)!;
      const ref = exemptionReference(s);
      const slot = before.find((x) => x.bookingId === skipped);
      const prevUsed = queue.find((e) => e.bookingId === skipped)!.postponeUsed;
      if (ref !== undefined && slot && postponeIsExempt(ref, slot.start, ctx.policy)) {
        next = next.map((e) => (e.bookingId === skipped ? { ...e, postponeUsed: prevUsed } : e));
      }
    }
    await this.commit(q, { ...ctx, queue }, next, skipped ? 'skipped' : 'started', [row.id], effects, c);
    ctx.queue = next;
    await this.event(q, c, row.id, 'service_started', { skipped, conflict }, conflict ? 'sync_conflict' : null);
    await emitBooking(q, ctx, row.id, 'booking_updated', effects);
    if (skipped) {
      await insertBookingEvent(q, { bookingId: skipped, type: 'postponed', payload: { steps: 1, skippedBy: row.id }, occurredAt: c.at, actorKind: 'staff', actorId: c.me.subjectId, reason: 'skipped' });
      // ق22: the skipped customer is no longer the called one — he waits to be called again.
      await q.query("UPDATE bookings SET called_at = NULL, last_change_reason = 'skipped', last_change_at = $2 WHERE id = $1", [skipped, new Date(c.now)]);
      await this.notifyPostponed(q, ctx, effects, skipped, 1);
      await emitBooking(q, ctx, skipped, 'booking_updated', effects);
    }
    if (conflict) {
      await q.query('INSERT INTO sync_conflicts (staff_id, booking_id, device_event_id, kind, details) VALUES ($1, $2, $3, $4, $5)', [
        c.me.subjectId,
        row.id,
        c.ev.id,
        'started_after_' + conflict,
        JSON.stringify({ previousStatus: conflict, cancelledAt: row.cancelled_at?.toISOString() ?? null, startedAt: new Date(c.at).toISOString() }),
      ]);
      await this.alertManagers(q, effects, c.me, row.id, conflict === 'cancelled' ? 'بدأت الخدمة بعد إلغاء الحجز' : 'بدأت الخدمة بعد تسجيل «لم يحضر»');
      return { flagged: true, reason: 'CONFLICT_ACTUAL_EVENT_WINS' };
    }
    return {};
  }

  private async finished(q: TenantQueryable, effects: Effects, c: EvCtx): Promise<Applied> {
    const row = await this.booking(q, c);
    if (row.status === 'done') throw new Reject('ALREADY_FINISHED');
    if (row.status !== 'in_service' || !row.actual_start) throw new Reject('NOT_IN_SERVICE');
    const ctx = await this.lockDay(q, c, row, effects);
    const start = row.actual_start.getTime();
    if (c.at < start) this.clamp(c, start); // L1: never before the start transition
    const end = c.at;
    await q.query("UPDATE bookings SET status = 'done', actual_end = $2, queue_position = NULL, updated_at = now() WHERE id = $1", [row.id, new Date(end)]);
    await this.commit(q, ctx, finishService(ctx.queue, row.id), 'finished', [row.id], effects, c);
    await this.event(q, c, row.id, 'service_finished', { durationSec: Math.round((end - start) / 1000) });
    // ق11: learn only from real start/finish taps; approximate (device restarted offline) times are excluded.
    const { rows: approxStart } = await q.query(
      "SELECT 1 FROM booking_events WHERE booking_id = $1 AND type = 'service_started' AND approximate_time LIMIT 1",
      [row.id],
    );
    // Round 2 (item 4): a service left unfinished when its day was closed is finished late — its
    // duration says nothing about the service, so it is never learned from.
    const afterClose = row.day_closed_at !== null;
    const measured = afterClose ? null : measuredDuration(start, end, { approximate: c.approximate || approxStart.length > 0 });
    await q.query(
      `INSERT INTO duration_samples (staff_id, service_set_key, customer_id, booking_id, duration_seconds, excluded, exclusion_reason)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [
        row.staff_id,
        row.service_set_key ?? '',
        row.customer_id,
        row.id,
        Math.max(0, Math.round((end - start) / 1000)),
        measured === null,
        measured === null
          ? afterClose
            ? 'after_day_close'
            : c.clamped
              ? 'clamped_time'
              : c.approximate || approxStart.length
                ? 'approximate_time'
                : 'invalid_times'
          : null,
      ],
    );
    if (afterClose) await resolveUnfinishedConflict(q, row.id, c.me.subjectId);
    if (measured !== null) await this.checkBaseDuration(q, effects, ctx, row);
    const { rows: svc } = await q.query<{ total: string }>('SELECT COALESCE(sum(price_minor), 0) AS total FROM booking_services WHERE booking_id = $1', [row.id]);
    await q.query('INSERT INTO payments (booking_id, amount_minor) VALUES ($1, $2) ON CONFLICT (booking_id) DO NOTHING', [row.id, Number(svc[0]!.total)]);
    await emitBooking(q, ctx, row.id, 'booking_updated', effects);
    await emitChange(q, effects, { staffId: row.staff_id, type: 'payment_updated', entity: 'payment', bookingId: row.id, data: { bookingId: row.id, status: 'awaiting_confirmation', amountCents: Number(svc[0]!.total) } });
    return {};
  }

  /**
   * Design §5.10: when most of a barber's recent samples for a service set fall outside the
   * plausible range around the configured base duration, the base is probably wrong — tell the
   * managers (once per service set and business day).
   */
  private async checkBaseDuration(q: TenantQueryable, effects: Effects, ctx: DayCtx, row: BookingRow): Promise<void> {
    const setKey = row.service_set_key ?? '';
    const { rows: svc } = await q.query<{ name: string; base: number }>(
      `SELECT bs.name_snapshot AS name, s.base_duration_minutes AS base
         FROM booking_services bs JOIN services s ON s.id = bs.service_id WHERE bs.booking_id = $1 ORDER BY bs.position`,
      [row.id],
    );
    if (!svc.length) return;
    const baseMin = svc.reduce((a, r) => a + r.base, 0);
    const { rows: samples } = await q.query<{ d: number }>(
      `SELECT duration_seconds AS d FROM duration_samples
        WHERE staff_id = $1 AND service_set_key = $2 AND NOT excluded ORDER BY recorded_at DESC, id LIMIT 20`,
      [row.staff_id, setKey],
    );
    const recent = samples.map((r) => r.d * 1000).reverse();
    if (!baseDurationSuspect(baseMin * MINUTE, recent)) return;
    await this.notifications.toManagers(q, effects, {
      type: 'base_duration_suspect',
      text: Texts.baseDurationSuspect(svc.map((r) => r.name).join(' + '), ctx.staff.name, baseMin),
      dedupeKey: `base_duration_suspect:${setKey}:${ctx.shift.workDate}`,
      data: { serviceSetKey: setKey, barberId: row.staff_id, baseDurationMin: String(baseMin) },
    });
  }

  /** ق9: always accepted; the session is not re-timed, only the estimate (and the price) change. */
  private async servicesChanged(q: TenantQueryable, effects: Effects, c: EvCtx): Promise<Applied> {
    const { serviceIds } = ServicesPayload.parse(c.ev.payload ?? {});
    const row = await this.booking(q, c);
    if (!['waiting', 'called', 'in_service', 'done'].includes(row.status)) throw new Reject('BOOKING_NOT_ACTIVE');
    const ctx = await this.lockDay(q, c, row, effects);
    let services;
    try {
      services = await resolveServices(q, serviceIds);
    } catch {
      throw new Reject('SERVICE_UNAVAILABLE');
    }
    const { durationMs, setKey } = await estimateFor(q, row.staff_id, row.customer_id, serviceIds, sumMinutes(services));
    if (row.status === 'done') {
      const { rows: pay } = await q.query<{ status: string }>('SELECT status FROM payments WHERE booking_id = $1 FOR UPDATE', [row.id]);
      if (pay[0]?.status === 'confirmed') throw new Reject('PAYMENT_ALREADY_CONFIRMED');
      await replaceBookingServices(q, row.id, services);
      await q.query('UPDATE bookings SET service_set_key = $2 WHERE id = $1', [row.id, setKey]);
      await q.query("UPDATE payments SET amount_minor = $2, updated_at = now() WHERE booking_id = $1 AND status = 'awaiting_confirmation'", [row.id, sumPrice(services)]);
      await this.event(q, c, row.id, 'services_changed', { serviceIds, priceCents: sumPrice(services) });
      await emitBooking(q, ctx, row.id, 'booking_updated', effects);
      return {};
    }
    await replaceBookingServices(q, row.id, services);
    await q.query('UPDATE bookings SET service_set_key = $2 WHERE id = $1', [row.id, setKey]);
    await this.commit(q, ctx, changeDuration(ctx.queue, row.id, durationMs), 'services_changed', [row.id], effects, c);
    await this.event(q, c, row.id, 'services_changed', { serviceIds, durationMin: Math.round(durationMs / MINUTE), priceCents: sumPrice(services) });
    await emitBooking(q, ctx, row.id, 'booking_updated', effects);
    return {};
  }

  /** Independent of the service state; confirming twice changes nothing (design §3). */
  private async paymentConfirmed(q: TenantQueryable, effects: Effects, c: EvCtx): Promise<Applied> {
    const { amount } = PaymentPayload.parse(c.ev.payload ?? {});
    const row = await this.booking(q, c, true);
    const { rows } = await q.query<{ id: string; status: string; amount_minor: string }>(
      'SELECT id, status, amount_minor FROM payments WHERE booking_id = $1 FOR UPDATE',
      [row.id],
    );
    const p = rows[0];
    if (!p) throw new Reject('NO_PAYMENT_YET');
    if (p.status === 'confirmed') {
      await this.event(q, c, row.id, 'payment_confirmed', { alreadyConfirmed: true });
      return { reason: 'ALREADY_CONFIRMED' };
    }
    // The server's price snapshot is the expected amount and is never overwritten by the device;
    // the amount the device reports is recorded next to it and a difference is flagged (review L2).
    const expected = Number(p.amount_minor);
    const confirmed = amount ?? expected;
    const discrepancy = confirmed !== expected;
    await q.query(
      `UPDATE payments SET status = 'confirmed', confirmed_amount_minor = $2, discrepancy = $5, confirmed_by_staff_id = $3, confirmed_at = $4, updated_at = now()
        WHERE id = $1`,
      [p.id, confirmed, c.me.subjectId, new Date(c.at), discrepancy],
    );
    await this.event(q, c, row.id, 'payment_confirmed', { amount: confirmed, expected, discrepancy });
    await writeAudit(q, {
      actorKind: 'staff', actorId: c.me.subjectId, action: 'payment.confirmed', targetKind: 'booking', targetId: row.id,
      details: { amount: confirmed, expected, discrepancy, viaDevice: true, ...recovered(c) },
    });
    await emitChange(q, effects, {
      staffId: row.staff_id,
      type: 'payment_updated',
      entity: 'payment',
      bookingId: row.id,
      data: { bookingId: row.id, status: 'confirmed', amountCents: expected, confirmedAmountCents: confirmed, discrepancy },
    });
    return discrepancy ? { reason: 'AMOUNT_DIFFERS_FROM_PRICE' } : {};
  }

  /** ق10/ق21/ق23: once per booking, N turns back, the next customer is called at once. */
  private async postponed(q: TenantQueryable, effects: Effects, c: EvCtx): Promise<Applied> {
    const { steps } = Steps.parse(c.ev.payload ?? {});
    const row = await this.booking(q, c);
    if (row.status === 'in_service') throw new Reject('IN_SERVICE');
    if (row.status !== 'waiting' && row.status !== 'called') throw new Reject('BOOKING_NOT_ACTIVE');
    const ctx = await this.lockDay(q, c, row, effects);
    const entry = ctx.queue.find((e) => e.bookingId === row.id);
    if (!entry) throw new Reject('BOOKING_NOT_ACTIVE');
    const ref = exemptionReference(ctx.byId.get(row.id) ?? row);
    const slot = project(ctx).find((s) => s.bookingId === row.id)!;
    const exempt = ref !== undefined && postponeIsExempt(ref, slot.start, ctx.policy);
    if (entry.postponeUsed && !exempt) throw new Reject('POSTPONE_ALREADY_USED');
    await this.commit(q, ctx, postpone(ctx.queue, row.id, steps, { exempt }), 'postponed_ahead', [row.id], effects, c);
    await q.query("UPDATE bookings SET called_at = NULL, last_change_reason = 'postponed', last_change_at = $2 WHERE id = $1", [row.id, new Date(c.now)]);
    await this.event(q, c, row.id, 'postponed', { steps, exempt }, exempt ? 'exempt_moved_earlier' : 'postponed');
    await this.callImmediately(q, ctx, effects, c);
    await this.notifyPostponed(q, ctx, effects, row.id, steps);
    await emitBooking(q, ctx, row.id, 'booking_updated', effects);
    return exempt ? { reason: 'POSTPONEMENT_NOT_COUNTED' } : {};
  }

  /** After the postponement the barber may keep waiting for the customer (design §5.6). */
  private async waited(q: TenantQueryable, _effects: Effects, c: EvCtx): Promise<Applied> {
    const row = await this.booking(q, c);
    if (row.status !== 'waiting' && row.status !== 'called') throw new Reject('BOOKING_NOT_ACTIVE');
    if (!row.postpone_used) throw new Reject('NOT_POSTPONED');
    await this.event(q, c, row.id, 'waited');
    return {};
  }

  /** ق10: «لم يحضر» only after the postponement was used. */
  private async noShow(q: TenantQueryable, effects: Effects, c: EvCtx): Promise<Applied> {
    const row = await this.booking(q, c);
    if (row.status === 'in_service') throw new Reject('IN_SERVICE');
    if (row.status !== 'waiting' && row.status !== 'called') throw new Reject('BOOKING_NOT_ACTIVE');
    const ctx = await this.lockDay(q, c, row, effects);
    const entry = ctx.queue.find((e) => e.bookingId === row.id);
    if (!entry) throw new Reject('BOOKING_NOT_ACTIVE');
    if (!canMarkNoShow(entry)) throw new Reject('NO_SHOW_BEFORE_POSTPONEMENT');
    await q.query("UPDATE bookings SET status = 'no_show', queue_position = NULL, updated_at = now() WHERE id = $1", [row.id]);
    await this.commit(q, ctx, remove(ctx.queue, row.id), 'no_show_ahead', [row.id], effects, c);
    await q.query('UPDATE customers SET no_show_count = no_show_count + 1, updated_at = now() WHERE id = $1', [row.customer_id]);
    await this.event(q, c, row.id, 'no_show');
    await this.notifications.toCustomer(q, effects, row.customer_id, { type: 'no_show', bookingId: row.id, text: Texts.noShow() });
    await emitBooking(q, ctx, row.id, 'booking_removed', effects);
    return {};
  }

  /** ق24: per affected booking — serve after closing, or cancel and tell the customer why. */
  private async closingDecision(q: TenantQueryable, effects: Effects, c: EvCtx): Promise<Applied> {
    const { decision, reason } = ClosingPayload.parse(c.ev.payload ?? {});
    const row = await this.booking(q, c);
    if (row.status !== 'waiting' && row.status !== 'called') throw new Reject('BOOKING_NOT_ACTIVE');
    const ctx = await this.lockDay(q, c, row, effects);
    if (decision === 'serve_late') {
      await q.query('UPDATE bookings SET serve_late = true, updated_at = now() WHERE id = $1', [row.id]);
      await this.event(q, c, row.id, 'closing_decision', { decision }, 'closing');
      await emitBooking(q, ctx, row.id, 'booking_updated', effects);
      return {};
    }
    const why = reason?.trim() || 'انتهى وقت الدوام';
    await q.query(
      "UPDATE bookings SET status = 'cancelled', queue_position = NULL, cancel_reason = $2, cancelled_at = $3, updated_at = now() WHERE id = $1",
      [row.id, `closing: ${why}`, new Date(c.at)],
    );
    await this.commit(q, ctx, remove(ctx.queue, row.id), 'cancelled_ahead', [row.id], effects, c);
    await this.event(q, c, row.id, 'closing_decision', { decision, reason: why }, 'closing');
    await writeAudit(q, { actorKind: 'staff', actorId: c.me.subjectId, action: 'booking.cancelled', targetKind: 'booking', targetId: row.id, details: { by: 'staff', reason: 'closing', ...recovered(c) } });
    await this.notifications.toCustomer(q, effects, row.customer_id, { type: 'cancelled_closing', bookingId: row.id, text: Texts.cancelledClosing(why) });
    await emitBooking(q, ctx, row.id, 'booking_removed', effects);
    return {};
  }

  private async breakStarted(q: TenantQueryable, effects: Effects, c: EvCtx): Promise<Applied> {
    const { kind, durationMin } = BreakPayload.parse(c.ev.payload ?? {});
    // An open break left over from an earlier day must not block today's (review, minor) — closed
    // under the day lock and before any change is emitted (lock order, round 2).
    const ctx = await this.lockToday(q, c, effects, (shift) => closeStaleOpenBreaks(q, c.t.salon.timezone, c.me.subjectId, c.now, effects, shift.workDate));
    const { rows: open } = await q.query('SELECT 1 FROM breaks WHERE staff_id = $1 AND open', [c.me.subjectId]);
    if (open.length) throw new Reject('BREAK_ALREADY_OPEN');
    const before = project(ctx);
    const { rows } = await q.query<{ id: string }>(
      `INSERT INTO breaks (staff_id, work_date, type, starts_at, ends_at, open, created_by_staff_id)
       VALUES ($1, $2, $3, $4, $5, true, $1) RETURNING id`,
      [c.me.subjectId, ctx.shift.workDate, kind, new Date(c.at), new Date(c.at + (durationMin ?? DEFAULT_BREAK_MIN) * MINUTE)],
    );
    const fresh = await loadDay(q, c.t.salon, c.me.subjectId, ctx.shift, c.now, { lock: true, settings: ctx.settings, staff: ctx.staff });
    await commitQueue(q, fresh, fresh.queue, { reason: 'barber_break', effects, actorKind: 'staff', actorId: c.me.subjectId, before });
    await this.event(q, c, null, 'break_started', { breakId: rows[0]!.id, kind, durationMin: durationMin ?? DEFAULT_BREAK_MIN });
    await emitChange(q, effects, { staffId: c.me.subjectId, type: 'break_started', entity: 'break', data: { breakId: rows[0]!.id, kind, start: new Date(c.at).toISOString() } });
    return {};
  }

  private async breakEnded(q: TenantQueryable, effects: Effects, c: EvCtx): Promise<Applied> {
    let rows: Array<{ id: string; starts_at: Date }> = [];
    const ctx = await this.lockToday(q, c, effects, async () => {
      rows = (await q.query<{ id: string; starts_at: Date }>('SELECT id, starts_at FROM breaks WHERE staff_id = $1 AND open FOR UPDATE', [c.me.subjectId])).rows;
    });
    const b = rows[0];
    if (!b) throw new Reject('NO_OPEN_BREAK');
    const before = project(ctx);
    await q.query('UPDATE breaks SET open = false, ends_at = $2 WHERE id = $1', [b.id, new Date(Math.max(c.at, b.starts_at.getTime() + 1000))]);
    const fresh = await loadDay(q, c.t.salon, c.me.subjectId, ctx.shift, c.now, { lock: true, settings: ctx.settings, staff: ctx.staff });
    await commitQueue(q, fresh, fresh.queue, { reason: 'break_ended', effects, actorKind: 'staff', actorId: c.me.subjectId, before });
    await this.event(q, c, null, 'break_ended', { breakId: b.id });
    await emitChange(q, effects, { staffId: c.me.subjectId, type: 'break_ended', entity: 'break', data: { breakId: b.id, end: new Date(c.at).toISOString() } });
    return {};
  }

  /** ق26: booking stops at this barber; the manager is told to move his bookings manually (ق25). */
  private async absent(q: TenantQueryable, effects: Effects, c: EvCtx): Promise<Applied> {
    const { reason } = AbsentPayload.parse(c.ev.payload ?? {});
    const ctx = await this.lockToday(q, c, effects);
    await q.query(
      `INSERT INTO absences (staff_id, work_date, reason, recorded_by_staff_id) VALUES ($1, $2, $3, $1)
       ON CONFLICT (staff_id, work_date) DO NOTHING`,
      [c.me.subjectId, ctx.shift.workDate, reason ?? null],
    );
    await q.query("UPDATE barber_days SET state = 'absent', updated_at = now() WHERE id = $1", [ctx.dayRow!.id]);
    await this.event(q, c, null, 'absent_today', { workDate: ctx.shift.workDate, reason: reason ?? null });
    await writeAudit(q, { actorKind: 'staff', actorId: c.me.subjectId, action: 'staff.absent_reported', targetKind: 'staff', targetId: c.me.subjectId, details: { workDate: ctx.shift.workDate, ...recovered(c) } });
    await emitChange(q, effects, { staffId: c.me.subjectId, type: 'day_state', entity: 'barber_day', data: { workDate: ctx.shift.workDate, state: stateWire({ kind: 'absent' }) } });
    const open = ctx.queue.filter((e) => !e.offer && e.status !== 'in_service').length;
    await this.notifications.toManagers(q, effects, {
      type: 'barber_absent',
      text: Texts.barberAbsent(ctx.staff.name, open),
      dedupeKey: `absent:${c.me.subjectId}:${ctx.shift.workDate}`,
      data: { barberId: c.me.subjectId },
    });
    return {};
  }

  // ─── ق40: recovery by a manager ────────────────────────────────────────────────────

  /**
   * ق40: a manager uploads, from the device of a SUSPENDED staff account, the events still in its
   * outbox. They are attributed to that account (ownership checks, actor, device events) and go
   * through the same state machine, once per event id; the device is the manager's session on it.
   * Only events whose corrected device time is strictly before the suspension are applied — flagged,
   * marked `recovered_by_staff_id` and listed for review; later ones are reported, not applied.
   * One audit entry summarises the upload.
   */
  async recoverBatch(
    t: TenantContext,
    manager: Principal,
    target: { id: string; role: 'barber' | 'manager'; suspendedAt: Date },
    events: DeviceEventIn[],
    ip: string | null,
  ): Promise<RecoveryResponse> {
    const as: Principal = { salonId: t.salonId, subjectId: target.id, role: target.role, sessionId: manager.sessionId };
    const suspendedAt = target.suspendedAt.getTime();
    const raw = await this.applyBatch(t, as, events, { recovery: { by: manager.subjectId, suspendedAt } });
    // A retry: tell the manager what happened to the event the first time.
    const dupIds = raw.filter((o) => o.result === 'duplicate').map((o) => o.eventId);
    const prior = new Map<string, { result: string; reason: string | null }>();
    if (dupIds.length) {
      const { rows } = await t.db.query<{ id: string; result: string; reason: string | null }>(
        'SELECT id, result, reason FROM device_events WHERE id = ANY($1::uuid[])',
        [dupIds],
      );
      for (const r of rows) prior.set(r.id, r);
    }
    const { results, summary } = recoveryOutcomes(raw, prior);
    await writeAudit(t, {
      actorKind: 'staff',
      actorId: manager.subjectId,
      action: 'staff.events_recovered',
      targetKind: 'staff',
      targetId: target.id,
      ip,
      details: {
        suspendedAt: target.suspendedAt.toISOString(),
        total: events.length,
        summary,
        appliedEventIds: results.filter((x) => x.result === 'applied').map((x) => x.eventId),
      },
    });
    return { staffId: target.id, suspendedAt: target.suspendedAt.toISOString(), results, summary };
  }

  // ─── Pull ──────────────────────────────────────────────────────────────────────────

  /** GET /sync?since= — changes for this barber (managers: the whole salon), in commit order. */
  async pull(t: TenantContext, me: Principal, since: number, limit = 500) {
    const upTo = await currentSeq(t.db); // read first: every seq ≤ upTo is committed (commit-ordered counter)
    const { rows } = await t.db.query<{ seq: string; type: string | null; entity: string; op: string; entity_id: string | null; data: Record<string, unknown> | null; created_at: Date }>(
      `SELECT seq, type, entity, op, entity_id, data, created_at FROM changes
        WHERE seq > $1 AND seq <= $2 AND ($3::boolean OR staff_id = $4 OR staff_id IS NULL)
        ORDER BY seq LIMIT $5`,
      [since, upTo, me.role === 'manager', me.subjectId, limit],
    );
    const full = rows.length === limit;
    return {
      changes: rows.map((r) => ({
        seq: Number(r.seq),
        type: r.type ?? `${r.entity}_${r.op}`,
        bookingId: r.entity === 'booking' || r.entity === 'payment' ? r.entity_id : null,
        data: r.data ?? {},
        occurredAt: r.created_at.toISOString(),
      })),
      seq: full ? Number(rows[rows.length - 1]!.seq) : Math.max(upTo, since),
      hasMore: full,
      serverTime: new Date(this.clock.now()).toISOString(),
    };
  }
}

/**
 * ق40: why a recovered event's (corrected) device time is refused, or null. It must be strictly
 * before the suspension, and — like a normal push — at most 48 h old, measured from the moment it
 * could last have been sent (the suspension, or now if earlier).
 */
export function recoveryTimeCheck(at: number, suspendedAt: number, now: number): string | null {
  if (at >= suspendedAt) return AFTER_SUSPENSION;
  if (at < Math.min(now, suspendedAt) - MAX_EVENT_AGE_MS) return 'EVENT_TOO_OLD';
  return null;
}

/**
 * ق40: maps the sync outcomes of a recovery upload to its per-event results. A duplicate (retry)
 * reports what happened to the event the first time (`prior` = its device_events row).
 */
export function recoveryOutcomes(
  raw: EventOutcome[],
  prior: Map<string, { result: string; reason: string | null }>,
): Pick<RecoveryResponse, 'results' | 'summary'> {
  const classify = (reason: string | null | undefined): RecoveryResult =>
    reason === AFTER_SUSPENSION ? 'rejected_after_suspension' : 'rejected_invalid';
  const results: RecoveryOutcome[] = raw.map((o) => {
    if (o.result === 'duplicate') {
      const p = prior.get(o.eventId);
      if (!p || p.result !== 'rejected') return { eventId: o.eventId, result: 'duplicate' };
      return { eventId: o.eventId, result: classify(p.reason), ...(p.reason ? { reason: p.reason } : {}) };
    }
    if (o.result === 'applied') return { eventId: o.eventId, result: 'applied', ...(o.reason ? { reason: o.reason } : {}) };
    return { eventId: o.eventId, result: classify(o.reason), ...(o.reason ? { reason: o.reason } : {}) };
  });
  const count = (r: RecoveryResult) => results.filter((x) => x.result === r).length;
  return {
    results,
    summary: {
      applied: count('applied'),
      duplicate: count('duplicate'),
      rejectedAfterSuspension: count('rejected_after_suspension'),
      rejectedInvalid: count('rejected_invalid'),
    },
  };
}

/** ق40: audit details marker for an event recovered by a manager. */
function recovered(c: EvCtx): Record<string, unknown> {
  return c.recoveredBy ? { recoveredByManager: c.recoveredBy } : {};
}

function isUuid(v: unknown): v is string {
  return typeof v === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
}

export const SyncErrors = {
  tooMany: () => new ApiError(HttpStatus.PAYLOAD_TOO_LARGE, 'TOO_MANY_EVENTS', 'دفعة أحداث كبيرة جدًا'),
};

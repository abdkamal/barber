import { remove } from '@saloni/engine';
import { NotificationService } from '../notifications/notification.service';
import { Texts } from '../notifications/texts';
import type { TenantContext, TenantQueryable } from '../tenancy/tenant-context';
import { BOOKING_SELECT, type BookingRow } from './rows';
import { emitBooking } from './booking-writer';
import { commitQueue, type DayWindow, type Effects, emitChange, insertBookingEvent, isStaleDay, loadDay, lockDayRow, schedulesOf, shiftOrDay } from './day';
import { PostCommit } from './post-commit';

/**
 * Review C1: active bookings of a business day that is over — the barber's next day has begun, or
 * (round 2) the grace after its shift end (`day_close_grace_minutes`) ran out — are closed out so they never show as current again. Waiting/called → cancelled (`day_closed`,
 * customer told); in service → kept for the barber to finish, flagged for the manager's review.
 * Offers of that day expire. Returns the number of days closed.
 */
export async function closeStaleDays(
  t: TenantContext,
  post: PostCommit,
  notifications: NotificationService,
  now: number,
  win: DayWindow,
): Promise<number> {
  const { rows: groups } = await t.db.query<{ staff_id: string; work_date: string }>(
    `SELECT DISTINCT staff_id, work_date::text AS work_date FROM bookings
      WHERE status IN ('offered', 'waiting', 'called', 'in_service') AND day_closed_at IS NULL
        AND work_date <= ($1::timestamptz AT TIME ZONE $2)::date
      ORDER BY staff_id, work_date`,
    [new Date(now), t.salon.timezone],
  );
  let closed = 0;
  for (const g of groups) {
    const schedules = await schedulesOf(t.db, g.staff_id);
    if (!isStaleDay(schedules, t.salon.timezone, g.work_date, now, win)) continue;
    await post.tx(t, (q, effects) => closeDay(q, effects, t, notifications, g.staff_id, shiftOrDay(schedules, t.salon.timezone, g.work_date), now));
    closed++;
  }
  return closed;
}

async function closeDay(
  q: TenantQueryable,
  effects: Effects,
  t: TenantContext,
  notifications: NotificationService,
  staffId: string,
  shift: ReturnType<typeof shiftOrDay>,
  now: number,
): Promise<void> {
  const ctx = await loadDay(q, t.salon, staffId, shift, now, { lock: true });
  let next = ctx.queue;
  const at = new Date(now);
  for (const r of ctx.rows) {
    if (r.day_closed_at) continue;
    if (r.status === 'offered') {
      await q.query(
        "UPDATE bookings SET status = 'expired', queue_position = NULL, cancel_reason = 'day_closed', day_closed_at = $2, updated_at = now() WHERE id = $1",
        [r.id, at],
      );
      next = remove(next, r.id);
      await emitBooking(q, ctx, r.id, 'booking_removed', effects);
      continue;
    }
    if (r.status === 'in_service') {
      await q.query('UPDATE bookings SET needs_review = true, day_closed_at = $2, updated_at = now() WHERE id = $1', [r.id, at]);
      await q.query('INSERT INTO sync_conflicts (staff_id, booking_id, kind, details) VALUES ($1, $2, $3, $4)', [
        staffId,
        r.id,
        'unfinished_at_day_close',
        JSON.stringify({ workDate: shift.workDate, actualStart: r.actual_start?.toISOString() ?? null }),
      ]);
      await insertBookingEvent(q, { bookingId: r.id, type: 'day_closed', payload: { status: r.status }, occurredAt: now, actorKind: 'system', reason: 'day_closed' });
      await emitBooking(q, ctx, r.id, 'booking_updated', effects);
      continue;
    }
    await q.query(
      `UPDATE bookings SET status = 'cancelled', queue_position = NULL, called_at = NULL, cancel_reason = 'day_closed',
              cancelled_at = $2, day_closed_at = $2, updated_at = now() WHERE id = $1`,
      [r.id, at],
    );
    next = remove(next, r.id);
    await insertBookingEvent(q, { bookingId: r.id, type: 'cancelled', payload: { previousStatus: r.status }, occurredAt: now, actorKind: 'system', reason: 'day_closed' });
    await notifications.toCustomer(q, effects, r.customer_id, { type: 'cancelled_closing', bookingId: r.id, text: Texts.dayClosed(), data: { reason: 'day_closed' } });
    await emitBooking(q, ctx, r.id, 'booking_removed', effects);
  }
  if (next.length !== ctx.queue.length) await commitQueue(q, ctx, next, { reason: 'day_closed', effects });
}

/**
 * Open device breaks (started on the barber's phone, never ended) are closed once their business
 * day is over — shift ended and nothing left to serve — so they neither stretch forever nor block
 * the next day's breaks (review, minor).
 *
 * Lock order (round 2): the caller MUST already hold the barber's day lock (lockDayRow / loadDay
 * with `lock`) and must not have emitted any change yet in this transaction — this locks the
 * barber's open `breaks` rows and then emits (change_counter). Every path therefore takes
 * barber-day row → breaks rows → change_counter, never the reverse.
 */
export async function closeStaleOpenBreaks(q: TenantQueryable, tz: string, staffId: string, now: number, effects: Effects, keepWorkDate?: string): Promise<void> {
  const { rows } = await q.query<{ id: string; work_date: string; starts_at: Date }>(
    'SELECT id, work_date::text AS work_date, starts_at FROM breaks WHERE staff_id = $1 AND open FOR UPDATE',
    [staffId],
  );
  if (!rows.length) return;
  const schedules = await schedulesOf(q, staffId);
  for (const b of rows) {
    if (b.work_date === keepWorkDate) continue;
    const shift = shiftOrDay(schedules, tz, b.work_date);
    if (now < shift.workEnd) continue;
    const { rows: active } = await q.query(
      `SELECT 1 FROM bookings WHERE staff_id = $1 AND work_date = $2 AND status IN ('waiting', 'called', 'in_service') AND day_closed_at IS NULL LIMIT 1`,
      [staffId, b.work_date],
    );
    if (active.length && keepWorkDate === undefined) continue; // the day is still operational (served after closing)
    const end = Math.max(b.starts_at.getTime() + 1000, Math.min(now, shift.workEnd));
    await q.query('UPDATE breaks SET open = false, ends_at = $2 WHERE id = $1', [b.id, new Date(end)]);
    await emitChange(q, effects, { staffId, type: 'break_ended', entity: 'break', data: { breakId: b.id, end: new Date(end).toISOString(), automatic: true } });
  }
}

/**
 * For a barber with no operational day (the scheduler): locks the day rows of his open breaks
 * (oldest first) and only then closes the stale ones — same lock order as every other path.
 */
export async function closeStaleOpenBreaksUnlocked(q: TenantQueryable, tz: string, staffId: string, now: number, effects: Effects): Promise<void> {
  const { rows } = await q.query<{ work_date: string }>(
    'SELECT DISTINCT work_date::text AS work_date FROM breaks WHERE staff_id = $1 AND open ORDER BY 1',
    [staffId],
  );
  if (!rows.length) return;
  for (const r of rows) await lockDayRow(q, staffId, r.work_date);
  await closeStaleOpenBreaks(q, tz, staffId, now, effects);
}

/**
 * Round 2 (item 4): services still `in_service` when their business day was closed out
 * (`needs_review`, conflict `unfinished_at_day_close`). The barber sees them in GET /staff/today
 * (`unfinishedFromPreviousDay`) and may finish them (sync `service_finished`, then payment); the
 * manager sees them in GET /manager/queues and pendingItems and may resolve them.
 */
export async function unfinishedFromClosedDays(q: TenantQueryable, staffId?: string): Promise<BookingRow[]> {
  const { rows } = await q.query<BookingRow>(
    `${BOOKING_SELECT}
      WHERE b.status = 'in_service' AND b.day_closed_at IS NOT NULL AND ($1::uuid IS NULL OR b.staff_id = $1)
      ORDER BY b.work_date, b.actual_start NULLS LAST, b.id`,
    [staffId ?? null],
  );
  return rows;
}

/** Marks the booking's `unfinished_at_day_close` conflict resolved (finished or cancelled). */
export async function resolveUnfinishedConflict(q: TenantQueryable, bookingId: string, byStaffId: string): Promise<void> {
  await q.query(
    `UPDATE sync_conflicts SET resolved_at = now(), resolved_by_staff_id = $2
      WHERE booking_id = $1 AND kind = 'unfinished_at_day_close' AND resolved_at IS NULL`,
    [bookingId, byStaffId],
  );
}

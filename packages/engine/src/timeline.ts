import type { BarberDay, Break, Ms, ProjectedSlot, Queue, QueueEntry } from './types.js';

const RANK = { in_service: 0, called: 1, waiting: 2 } as const;

/** Throws if the queue breaks the in_service → called → waiting ordering. */
export function assertQueueShape(queue: Queue): void {
  let inService = 0;
  let called = 0;
  const seen = new Set<string>();
  for (let i = 0; i < queue.length; i++) {
    const e = queue[i]!;
    if (seen.has(e.bookingId)) throw new Error(`duplicate booking ${e.bookingId}`);
    seen.add(e.bookingId);
    if (e.status === 'in_service') inService++;
    if (e.status === 'called') called++;
    if (i > 0 && RANK[e.status] < RANK[queue[i - 1]!.status]) {
      throw new Error(`queue out of order at ${e.bookingId}`);
    }
    if (e.kind === 'requested' && e.requestedAt === undefined) {
      throw new Error(`requested booking ${e.bookingId} has no requestedAt`);
    }
    if (e.status === 'in_service' && e.actualStart === undefined) {
      throw new Error(`in-service booking ${e.bookingId} has no actualStart`);
    }
    if (!(e.estimatedDuration > 0)) throw new Error(`booking ${e.bookingId} has no duration`);
  }
  if (inService > 1) throw new Error('more than one booking in service');
  if (called > 1) throw new Error('more than one booking called');
}

/** The breaks that block this entry: walk-ins may use walk-in-only windows (ق33). */
export function blockingBreaks(breaks: readonly Break[], walkIn: boolean): Break[] {
  return walkIn ? breaks.filter((b) => b.kind !== 'walk_in_only') : [...breaks];
}

/**
 * Earliest start ≥ `from` at which a service of `duration` fits entirely
 * outside every break. A service never straddles a break.
 */
export function fitAroundBreaks(from: Ms, duration: Ms, breaks: readonly Break[]): Ms {
  let start = from;
  let moved = true;
  while (moved) {
    moved = false;
    for (const b of breaks) {
      if (start < b.end && start + duration > b.start) {
        start = b.end;
        moved = true;
      }
    }
  }
  return start;
}

export interface ProjectOptions {
  /**
   * Design §4: when the barber is offline or not connected yet, the server
   * cannot see progress. Project from this moment using estimates only —
   * no stretching of an overrunning service — so customers are not sent
   * false "your time changed" notices.
   */
  frozenAt?: Ms;
}

/**
 * Projects start/end times for every booking in the queue, in order.
 *
 * - The booking in service ends at `actualStart + estimate`, or `now` if it
 *   has already overrun and the barber is live (never ended automatically).
 *   When frozen (barber not live), the overrun is not stretched — the server
 *   cannot see it — but no waiting booking is ever projected into the past.
 * - A service that runs into a break pushes that break later by the overlap:
 *   the barber still takes the full break after finishing (design §5.1).
 * - Everyone else starts when the previous one ends, not before opening time,
 *   not before `now`, not before their requested hour, and never across a
 *   break that blocks them.
 */
export function projectQueue(day: BarberDay, queue: Queue, now: Ms, opts: ProjectOptions = {}): ProjectedSlot[] {
  const live = opts.frozenAt === undefined;
  const slots: ProjectedSlot[] = [];
  let effectiveDay = day;
  let cursor = Math.max(now, day.workStart);
  for (const e of queue) {
    if (e.status === 'in_service') {
      const start = e.actualStart!;
      const end = live ? Math.max(start + e.estimatedDuration, now) : start + e.estimatedDuration;
      slots.push({ bookingId: e.bookingId, start, end });
      cursor = Math.max(cursor, end);
      effectiveDay = { ...day, breaks: shiftOverrunBreak(day.breaks, start, end) };
      continue;
    }
    slots.push(slotFor(e, cursor, effectiveDay));
    cursor = slots[slots.length - 1]!.end;
  }
  return slots;
}

/**
 * The first real break (not a walk-in-only window) that a running service
 * overlaps is moved to start when the service ends, keeping its full length.
 */
export function shiftOverrunBreak(breaks: readonly Break[], serviceStart: Ms, serviceEnd: Ms): Break[] {
  let shifted = false;
  return breaks.map((b) => {
    if (shifted || b.kind === 'walk_in_only') return b;
    if (serviceStart < b.start && serviceEnd > b.start) {
      shifted = true;
      return { ...b, start: serviceEnd, end: serviceEnd + (b.end - b.start) };
    }
    return b;
  });
}

function slotFor(e: QueueEntry, cursor: Ms, day: BarberDay): ProjectedSlot {
  let earliest = cursor;
  if (e.kind === 'requested') earliest = Math.max(earliest, e.requestedAt!);
  const start = fitAroundBreaks(earliest, e.estimatedDuration, blockingBreaks(day.breaks, !!e.walkIn));
  return { bookingId: e.bookingId, start, end: start + e.estimatedDuration };
}

/** Projected end of all work in the queue (or `now`/opening if empty). */
export function queueEnd(day: BarberDay, queue: Queue, now: Ms, opts: ProjectOptions = {}): Ms {
  const slots = projectQueue(day, queue, now, opts);
  return slots.length ? slots[slots.length - 1]!.end : Math.max(now, day.workStart);
}

/** ق24: accepted bookings now projected to end after closing. */
export function pastClosing(day: BarberDay, slots: readonly ProjectedSlot[]): string[] {
  return slots.filter((s) => s.end > day.workEnd).map((s) => s.bookingId);
}

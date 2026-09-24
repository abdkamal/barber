import { DEFAULT_POLICY, gapBuffer, type PolicySettings } from './policy.js';
import { blockingBreaks, projectQueue, type ProjectOptions } from './timeline.js';
import type { BarberDay, BookingKind, Ms, ProjectedSlot, Queue, QueueEntry } from './types.js';

export interface PlacementRequest {
  kind: BookingKind;
  /** Required when `kind === 'requested'`. */
  requestedAt?: Ms;
  /** Duration estimate for this customer/service at this barber. */
  duration: Ms;
  /** Added by the barber for a customer in the salon (may use walk-in-only windows). */
  walkIn?: boolean;
}

export interface PlacementOptions extends ProjectOptions {
  /** ق3: offline barber — new bookings may only go to the end of the queue. */
  appendOnly?: boolean;
  policy?: PolicySettings;
}

export interface Placement {
  /** Index in the queue at which the new booking is inserted. */
  position: number;
  start: Ms;
  end: Ms;
}

const NEW_ID = '__new__';

/**
 * Finds where a new booking goes in a barber's queue.
 *
 * ق4: it may never delay the projected start of any existing booking, not even
 * by a minute — so it is appended, unless a real gap fits it untouched.
 * ق19: a gap is only used if it is larger than the service by a safety buffer,
 * so that an ordinary overrun is still absorbed by the gap.
 * It is never placed ahead of the booking in service or the one called, and it
 * must finish before the barber's day ends.
 *
 * Returns the earliest-starting valid placement (ties: the later position,
 * jumping as few people as possible), or null.
 */
export function findPlacement(day: BarberDay, queue: Queue, now: Ms, req: PlacementRequest, opts: PlacementOptions = {}): Placement | null {
  if (req.kind === 'requested' && req.requestedAt === undefined) throw new Error('requested placement needs requestedAt');
  if (!(req.duration > 0)) throw new Error('placement needs a positive duration');
  const policy = opts.policy ?? DEFAULT_POLICY;
  const baseline = byId(projectQueue(day, queue, now, opts));
  const firstInsertable = queue.filter((e) => e.status !== 'waiting').length;
  const from = opts.appendOnly ? queue.length : firstInsertable;
  const buffer = gapBuffer(req.duration, policy);

  const entry: QueueEntry = {
    bookingId: NEW_ID,
    kind: req.kind,
    requestedAt: req.requestedAt,
    status: 'waiting',
    estimatedDuration: req.duration,
    walkIn: req.walkIn,
  };

  let best: Placement | null = null;
  for (let p = from; p <= queue.length; p++) {
    const slots = projectQueue(day, insertAt(queue, p, entry), now, opts);
    const mine = slots[p]!;
    if (mine.end > day.workEnd) continue;
    if (slots.some((s) => s.bookingId !== NEW_ID && s.start > baseline.get(s.bookingId)!.start)) continue;
    const next = slots[p + 1];
    if (next) {
      // ق19: the slack protecting whoever follows ends at the next booking or
      // at a break in between, whichever comes first.
      const breakAfter = blockingBreaks(day.breaks, !!req.walkIn)
        .filter((b) => b.start >= mine.end && b.start < next.start)
        .reduce((m, b) => Math.min(m, b.start), Infinity);
      if (Math.min(next.start, breakAfter) - mine.end < buffer) continue;
    }
    if (!best || mine.start <= best.start) best = { position: p, start: mine.start, end: mine.end };
  }
  return best;
}

export function insertAt(queue: Queue, position: number, entry: QueueEntry): QueueEntry[] {
  return [...queue.slice(0, position), entry, ...queue.slice(position)];
}

function byId(slots: ProjectedSlot[]): Map<string, ProjectedSlot> {
  return new Map(slots.map((s) => [s.bookingId, s]));
}

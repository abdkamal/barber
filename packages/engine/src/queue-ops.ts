import { findPlacement, insertAt, type PlacementOptions, type PlacementRequest } from './placement.js';
import type { BarberDay, Ms, ProjectedSlot, Queue, QueueEntry } from './types.js';

/**
 * Design §5.5 — per barber, one customer in service and one called; never a
 * third just because the called one has not arrived. The next waiting customer
 * is called once their projected start is within the barber's lead time, or
 * immediately after a postponement (ق21).
 */
export function selectToCall(
  queue: Queue,
  slots: readonly ProjectedSlot[],
  now: Ms,
  leadTime: Ms,
  opts: { immediate?: boolean } = {},
): string | null {
  if (queue.some((e) => e.status === 'called')) return null;
  const idx = queue.findIndex((e) => e.status === 'waiting' && !e.offer);
  if (idx < 0) return null;
  const slot = slots[idx]!;
  return opts.immediate || slot.start - now <= leadTime ? slot.bookingId : null;
}

function indexOf(queue: Queue, bookingId: string): number {
  const i = queue.findIndex((e) => e.bookingId === bookingId);
  if (i < 0) throw new Error(`booking ${bookingId} not in queue`);
  return i;
}

function patch(queue: Queue, i: number, p: Partial<QueueEntry>): QueueEntry[] {
  return queue.map((e, j) => (j === i ? { ...e, ...p } : e));
}

export function markCalled(queue: Queue, bookingId: string): QueueEntry[] {
  const i = indexOf(queue, bookingId);
  if (queue[i]!.status !== 'waiting') throw new Error('only a waiting booking can be called');
  if (queue.some((e) => e.status === 'called')) throw new Error('another booking is already called');
  return patch(queue, i, { status: 'called' });
}

export interface StartResult {
  queue: QueueEntry[];
  /** ق22: the called customer the barber skipped — counts as their postponement and is notified. */
  skipped: string | null;
}

/**
 * Barber taps "start service". Starting proves presence (no arrival check).
 * The barber may start any present customer; the booking moves to the front.
 * If someone else was called, they go back to waiting in their place — one turn
 * later — and that counts as their postponement (ق22).
 */
export function startService(queue: Queue, bookingId: string, at: Ms): StartResult {
  if (queue.some((e) => e.status === 'in_service')) throw new Error('finish the current service first');
  const i = indexOf(queue, bookingId);
  if (queue[i]!.offer) throw new Error('an unconfirmed offer cannot be started');
  const calledId = queue.find((e) => e.status === 'called')?.bookingId ?? null;
  const skipped = calledId && calledId !== bookingId ? calledId : null;
  const started: QueueEntry = { ...queue[i]!, status: 'in_service', actualStart: at };
  const rest = queue
    .filter((_, j) => j !== i)
    .map((e): QueueEntry => (e.bookingId === skipped ? { ...e, status: 'waiting', postponeUsed: true } : e));
  return { queue: [started, ...rest], skipped };
}

/** Barber taps "end service". The booking leaves the queue; payment is tracked separately. */
export function finishService(queue: Queue, bookingId: string): QueueEntry[] {
  const i = indexOf(queue, bookingId);
  if (queue[i]!.status !== 'in_service') throw new Error('booking is not in service');
  return queue.filter((_, j) => j !== i);
}

/** ق9: services changed mid-session — only the estimate changes; timing is not restarted. */
export function changeDuration(queue: Queue, bookingId: string, duration: Ms): QueueEntry[] {
  if (!(duration > 0)) throw new Error('duration must be positive');
  return patch(queue, indexOf(queue, bookingId), { estimatedDuration: duration });
}

export function canPostpone(entry: QueueEntry): boolean {
  return entry.status !== 'in_service' && !entry.postponeUsed && !entry.offer;
}

/** ق10: «لم يحضر» only after the postponement was used. */
export function canMarkNoShow(entry: QueueEntry): boolean {
  return entry.status !== 'in_service' && !!entry.postponeUsed;
}

/**
 * ق10/ق21: the barber pushes a late customer back `steps` turns — once per
 * booking. A called customer returns to waiting, so the next can be called at
 * once. `exempt` (ق23): lateness caused by being moved earlier does not use
 * up the postponement.
 */
export function postpone(queue: Queue, bookingId: string, steps = 1, opts: { exempt?: boolean } = {}): QueueEntry[] {
  if (!Number.isInteger(steps) || steps < 1) throw new Error('steps must be a positive integer');
  const i = indexOf(queue, bookingId);
  const e = queue[i]!;
  if (e.status === 'in_service') throw new Error('cannot postpone a booking in service');
  if (e.postponeUsed && !opts.exempt) throw new Error('postponement already used');
  const moved: QueueEntry = { ...e, status: 'waiting', postponeUsed: e.postponeUsed || !opts.exempt };
  const rest = queue.filter((_, j) => j !== i);
  const target = Math.min(i + steps, rest.length);
  return [...rest.slice(0, target), moved, ...rest.slice(target)];
}

/** Customer cancels (ق29: any time before service starts), barber marks no-show, or an offer expires. */
export function remove(queue: Queue, bookingId: string): QueueEntry[] {
  const i = indexOf(queue, bookingId);
  if (queue[i]!.status === 'in_service') throw new Error('cannot remove a booking in service');
  return queue.filter((_, j) => j !== i);
}

/** ق13: the customer accepted the held offer — it becomes a normal booking in place. */
export function confirmOffer(queue: Queue, bookingId: string): QueueEntry[] {
  const i = indexOf(queue, bookingId);
  if (!queue[i]!.offer) throw new Error('not an offer');
  return patch(queue, i, { offer: false });
}

/**
 * Design §5.12 — the customer asks for another time: one atomic re-insertion
 * under ق4. Returns the new queue, or null if the new time does not fit (then
 * the old booking stays exactly as it was).
 */
export function changeTime(
  day: BarberDay,
  queue: Queue,
  now: Ms,
  bookingId: string,
  req: Omit<PlacementRequest, 'duration'>,
  opts: PlacementOptions = {},
): { queue: QueueEntry[]; start: Ms } | null {
  const i = indexOf(queue, bookingId);
  const e = queue[i]!;
  if (e.status !== 'waiting') return null;
  const without = queue.filter((_, j) => j !== i);
  const p = findPlacement(day, without, now, { ...req, duration: e.estimatedDuration, walkIn: e.walkIn }, opts);
  if (!p) return null;
  const moved: QueueEntry = { ...e, kind: req.kind, requestedAt: req.kind === 'requested' ? req.requestedAt : undefined };
  return { queue: insertAt(without, p.position, moved), start: p.start };
}

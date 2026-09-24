import { bookingGate, DEFAULT_POLICY, type PolicySettings } from './policy.js';
import { findPlacement, type Placement, type PlacementRequest } from './placement.js';
import type { BarberDay, BarberDayState, Ms, Queue } from './types.js';

export interface BarberCandidate {
  day: BarberDay;
  queue: Queue;
  state: BarberDayState;
  /** This customer's duration estimate for the service at this barber. */
  duration: Ms;
  /** Bookings taken today — a tie-break. */
  bookingsToday: number;
  /** Order the barber was added to the salon — the final, stable tie-break. */
  seniority: number;
}

export interface Assignment extends Placement {
  barberId: string;
}

/**
 * Design §5.4 — auto-assign ("الأسرع"): the barber expected to *start* this
 * service soonest, with this customer's own duration at each barber; ties go to
 * the earlier finish, then fewer bookings today, then seniority.
 * Offline and absent barbers are skipped (design §4). Once assigned, the
 * barber is fixed; there is never an automatic transfer later.
 */
export function chooseBarber(
  candidates: readonly BarberCandidate[],
  now: Ms,
  req: Omit<PlacementRequest, 'duration'>,
  policy: PolicySettings = DEFAULT_POLICY,
): Assignment | null {
  let best: (Assignment & { c: BarberCandidate }) | null = null;
  for (const c of candidates) {
    const gate = bookingGate(c.state, now, policy);
    if (!gate.accepts || !gate.autoAssignable) continue;
    const p = findPlacement(c.day, c.queue, now, { ...req, duration: c.duration }, { appendOnly: gate.appendOnly, frozenAt: gate.frozenAt, policy });
    if (!p) continue;
    const a = { ...p, barberId: c.day.barberId, c };
    if (!best || compare(a, best) < 0) best = a;
  }
  if (!best) return null;
  const { c: _c, ...assignment } = best;
  return assignment;
}

function compare(a: Assignment & { c: BarberCandidate }, b: Assignment & { c: BarberCandidate }): number {
  return a.start - b.start || a.end - b.end || a.c.bookingsToday - b.c.bookingsToday || a.c.seniority - b.c.seniority;
}

/** A booking for one specific barber (chosen by the customer, or a walk-in, or a manual transfer). */
export function placeWithBarber(
  c: Omit<BarberCandidate, 'bookingsToday' | 'seniority'>,
  now: Ms,
  req: Omit<PlacementRequest, 'duration'>,
  policy: PolicySettings = DEFAULT_POLICY,
): Placement | null {
  const gate = bookingGate(c.state, now, policy);
  // Walk-ins are added by the barber on his device while online (ق3: never offline).
  if (!gate.accepts) return null;
  return findPlacement(c.day, c.queue, now, { ...req, duration: c.duration }, { appendOnly: gate.appendOnly, frozenAt: gate.frozenAt, policy });
}

import { HOUR, MINUTE, type BarberDayState, type Ms, type ProjectedSlot } from './types.js';

/** Salon-level settings for the agreed rules. Defaults follow docs/decisions.md and design §11. */
export interface PolicySettings {
  /** ق5: change in expected time that obliges a notification. */
  changeMargin: Ms;
  /** ق3: remote bookings to an offline barber stop after this long. */
  maxOfflineWindow: Ms;
  /** ق19: a gap is filled only if it exceeds the service by max(min, ratio × duration). */
  gapBufferMin: Ms;
  gapBufferRatio: number;
  /** ق13: how long an offered time is held. */
  offerHold: Ms;
  /** ق27: warn the barber when elapsed ≥ ratio × estimate. */
  overrunAlertRatio: number;
}

export const DEFAULT_POLICY: PolicySettings = {
  changeMargin: 30 * MINUTE,
  maxOfflineWindow: 2 * HOUR,
  gapBufferMin: 10 * MINUTE,
  gapBufferRatio: 0.25,
  offerHold: 2 * MINUTE,
  overrunAlertRatio: 1,
};

export function gapBuffer(duration: Ms, policy: PolicySettings = DEFAULT_POLICY): Ms {
  return Math.max(policy.gapBufferMin, Math.round(duration * policy.gapBufferRatio));
}

/** ق13: exact hour → book it; anything later → offer the nearest time only. */
export function requestedHourOutcome(start: Ms, requestedAt: Ms): 'accept' | 'offer' {
  return start <= requestedAt ? 'accept' : 'offer';
}

/**
 * ق5/ق23: the customer must be told when the expected start moved by more
 * than the margin — earlier or later — from the time they last saw.
 */
export function needsNotification(lastCommunicated: Ms, newStart: Ms, policy: PolicySettings = DEFAULT_POLICY): boolean {
  return Math.abs(newStart - lastCommunicated) > policy.changeMargin;
}

/** ق23: lateness caused by being moved earlier by more than the margin does not use up the postponement. */
export function postponeIsExempt(lastCommunicated: Ms, slotStart: Ms, policy: PolicySettings = DEFAULT_POLICY): boolean {
  return slotStart < lastCommunicated - policy.changeMargin;
}

/** ق27: the barber is reminded (never auto-ended) once the service reaches its estimate. */
export function overrunAlert(actualStart: Ms, estimate: Ms, now: Ms, policy: PolicySettings = DEFAULT_POLICY): boolean {
  return now - actualStart >= estimate * policy.overrunAlertRatio;
}

export interface SlotChange {
  bookingId: string;
  before: Ms;
  after: Ms;
  delta: Ms;
}

/** Bookings whose projected start changed — for the ق9 impact preview and the audit log. */
export function diffProjections(before: readonly ProjectedSlot[], after: readonly ProjectedSlot[]): SlotChange[] {
  const prev = new Map(before.map((s) => [s.bookingId, s.start]));
  const changes: SlotChange[] = [];
  for (const s of after) {
    const b = prev.get(s.bookingId);
    if (b !== undefined && b !== s.start) changes.push({ bookingId: s.bookingId, before: b, after: s.start, delta: s.start - b });
  }
  return changes;
}

/**
 * ق3 (confirmed): if the barber had at least two hours of known work when the
 * connection dropped, remote bookings keep coming (appended) until two hours
 * have passed; with less, they stop immediately.
 */
export function offlineBookingDeadline(offlineSince: Ms, knownWorkEnd: Ms, policy: PolicySettings = DEFAULT_POLICY): Ms {
  const knownWork = knownWorkEnd - offlineSince;
  return knownWork >= policy.maxOfflineWindow ? offlineSince + policy.maxOfflineWindow : offlineSince;
}

export interface BookingGate {
  /** New remote bookings accepted for this barber. */
  accepts: boolean;
  /** Only at the end of the queue (offline barber). */
  appendOnly: boolean;
  /** Eligible for automatic assignment (design §4: never offline or absent barbers). */
  autoAssignable: boolean;
  /** Project with estimates only, from this time. */
  frozenAt?: Ms;
}

/** Design §4 + ق26: what the barber's day state allows. */
export function bookingGate(state: BarberDayState, now: Ms, policy: PolicySettings = DEFAULT_POLICY): BookingGate {
  switch (state.kind) {
    case 'online':
      return { accepts: true, appendOnly: false, autoAssignable: true };
    case 'not_connected':
      // ق26: booking opens normally — the barber is expected per his schedule.
      return { accepts: true, appendOnly: false, autoAssignable: true, frozenAt: now };
    case 'absent':
      return { accepts: false, appendOnly: false, autoAssignable: false };
    case 'offline': {
      const deadline = offlineBookingDeadline(state.offlineSince, state.knownWorkEnd, policy);
      return { accepts: now < deadline, appendOnly: true, autoAssignable: false, frozenAt: state.offlineSince };
    }
  }
}

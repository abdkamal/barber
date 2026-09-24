/** Absolute time in epoch milliseconds. */
export type Ms = number;

export const MINUTE: Ms = 60_000;
export const HOUR: Ms = 60 * MINUTE;

export interface Interval {
  start: Ms;
  end: Ms;
}

/**
 * - `break`: rest, prayer, emergency — nobody is served.
 * - `walk_in_only` (ق33): closed to app bookings, open to walk-ins the barber adds.
 */
export type BreakKind = 'break' | 'walk_in_only';

export interface Break extends Interval {
  kind?: BreakKind;
}

/** A barber's working day (ق30: may run past midnight — times are absolute). */
export interface BarberDay {
  barberId: string;
  workStart: Ms;
  workEnd: Ms;
  breaks: Break[];
}

/**
 * - `queue`: a plain turn — served as soon as possible.
 * - `requested`: the customer asked for a specific hour; never starts before it.
 */
export type BookingKind = 'queue' | 'requested';

/** Statuses of a booking still in a barber's queue (offers hold a place too). */
export type ActiveStatus = 'waiting' | 'called' | 'in_service';

export interface QueueEntry {
  bookingId: string;
  kind: BookingKind;
  /** Only for `requested` bookings. */
  requestedAt?: Ms;
  status: ActiveStatus;
  /** Current duration estimate for the booking's (current) services. */
  estimatedDuration: Ms;
  /** Set once the barber taps "start service". */
  actualStart?: Ms;
  /** Added by the barber for a customer in the salon; may use walk-in-only windows. */
  walkIn?: boolean;
  /** ق10/ق21: the single postponement has been used. */
  postponeUsed?: boolean;
  /** A tentative offer (ق13) holding its place for a short time. */
  offer?: boolean;
}

/**
 * A barber's queue in service order. Invariant (see `assertQueueShape`):
 * at most one `in_service` (first), then at most one `called`, then `waiting`.
 */
export type Queue = readonly QueueEntry[];

export interface ProjectedSlot {
  bookingId: string;
  start: Ms;
  end: Ms;
}

/** Design §4 — how much the server knows about a barber right now. */
export type BarberDayState =
  | { kind: 'not_connected' }
  | { kind: 'online' }
  | { kind: 'offline'; offlineSince: Ms; knownWorkEnd: Ms }
  | { kind: 'absent' };

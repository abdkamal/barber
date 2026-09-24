/**
 * Work-day simulator (design §5, implementation plan milestone 1).
 * Drives the real engine through a synthetic day to tune the open numbers
 * (buffers, lead times) on outcomes instead of guesses. Not shipped to apps.
 */
import { chooseBarber, type BarberCandidate } from '../assignment.js';
import { DEFAULT_POLICY, needsNotification, type PolicySettings } from '../policy.js';
import { insertAt } from '../placement.js';
import { finishService, markCalled, postpone, remove, selectToCall, startService } from '../queue-ops.js';
import { projectQueue } from '../timeline.js';
import { HOUR, MINUTE, type BarberDay, type Ms, type QueueEntry } from '../types.js';

export interface SimConfig {
  seed: number;
  barbers: number;
  /** Mean booking requests per hour for the whole salon. */
  demandPerHour: number;
  /** Share of requests that ask for a specific hour. */
  requestedShare: number;
  /** Chance a called customer is late enough that the barber postpones. */
  lateChance: number;
  /** Chance a customer cancels before being served. */
  cancelChance: number;
  /** Barber lead time for calling. */
  leadTime: Ms;
  /** Spread of real durations around the estimate (log-normal sigma). */
  durationSigma: number;
  policy: PolicySettings;
}

export const DEFAULT_SIM: SimConfig = {
  seed: 1,
  barbers: 3,
  demandPerHour: 7,
  requestedShare: 0.2,
  lateChance: 0.1,
  cancelChance: 0.05,
  leadTime: 20 * MINUTE,
  durationSigma: 0.2,
  policy: DEFAULT_POLICY,
};

interface Booking {
  id: string;
  barberId: string;
  estimate: Ms;
  real: Ms;
  firstEta: Ms;
  lastCommunicated: Ms;
  notifications: number;
  late: boolean;
  startedAt?: Ms;
  cancelled?: boolean;
  noShow?: boolean;
}

export interface SimReport {
  requests: number;
  accepted: number;
  refused: number;
  served: number;
  cancelled: number;
  noShows: number;
  /** Mean |actual start − first ETA| in minutes. */
  meanEtaErrorMin: number;
  p90EtaErrorMin: number;
  /** Share of served customers who received at least one ≥30-min change notice. */
  notifiedShare: number;
  /** Mean share of the working day barbers spent serving. */
  utilization: number;
}

function rng(seed: number) {
  let s = seed >>> 0 || 1;
  return () => {
    s ^= s << 13;
    s ^= s >>> 17;
    s ^= s << 5;
    return (s >>> 0) / 4294967296;
  };
}

export function simulate(cfg: SimConfig = DEFAULT_SIM): SimReport {
  const rand = rng(cfg.seed);
  const gauss = () => Math.sqrt(-2 * Math.log(rand() || 1e-9)) * Math.cos(2 * Math.PI * rand());
  const open = Date.UTC(2026, 0, 1, 10);
  const close = open + 12 * HOUR;
  const services = [20, 30, 45].map((m) => m * MINUTE);

  const days: BarberDay[] = Array.from({ length: cfg.barbers }, (_, i) => ({
    barberId: `b${i}`,
    workStart: open,
    workEnd: close,
    breaks: [{ start: open + 3 * HOUR, end: open + 3 * HOUR + 20 * MINUTE }],
  }));
  const queues = new Map<string, QueueEntry[]>(days.map((d) => [d.barberId, []]));
  const pace = new Map(days.map((d, i) => [d.barberId, 0.85 + 0.1 * i]));
  const busy = new Map(days.map((d) => [d.barberId, 0]));
  const bookings = new Map<string, Booking>();
  let requests = 0;
  let refused = 0;
  let seq = 0;

  for (let now = open - HOUR; now < close + 2 * HOUR; now += MINUTE) {
    // New requests (Poisson per minute), only before closing.
    if (now < close && rand() < cfg.demandPerHour / 60) {
      requests++;
      const base = services[Math.floor(rand() * services.length)]!;
      const isReq = rand() < cfg.requestedShare;
      const at = Math.max(now, open) + Math.floor(rand() * 5) * HOUR;
      const cands: BarberCandidate[] = days.map((d, i) => ({
        day: d,
        queue: queues.get(d.barberId)!,
        state: { kind: 'online' },
        duration: base,
        bookingsToday: [...bookings.values()].filter((b) => b.barberId === d.barberId).length,
        seniority: i,
      }));
      const a = chooseBarber(cands, now, isReq ? { kind: 'requested', requestedAt: at } : { kind: 'queue' }, cfg.policy);
      if (!a) refused++;
      else {
        const id = `k${seq++}`;
        const entry: QueueEntry = isReq
          ? { bookingId: id, kind: 'requested', requestedAt: a.start, status: 'waiting', estimatedDuration: base }
          : { bookingId: id, kind: 'queue', status: 'waiting', estimatedDuration: base };
        queues.set(a.barberId, insertAt(queues.get(a.barberId)!, a.position, entry));
        const real = Math.max(5 * MINUTE, base * pace.get(a.barberId)! * Math.exp(cfg.durationSigma * gauss()));
        bookings.set(id, { id, barberId: a.barberId, estimate: base, real, firstEta: a.start, lastCommunicated: a.start, notifications: 0, late: rand() < cfg.lateChance });
      }
    }

    for (const d of days) {
      let queue = queues.get(d.barberId)!;
      // Random cancellations of waiting customers.
      for (const e of queue) {
        if (e.status === 'waiting' && rand() < cfg.cancelChance / 240) {
          queue = remove(queue, e.bookingId);
          bookings.get(e.bookingId)!.cancelled = true;
        }
      }
      const head = queue[0];
      if (head?.status === 'in_service') {
        busy.set(d.barberId, busy.get(d.barberId)! + MINUTE);
        const b = bookings.get(head.bookingId)!;
        if (now - b.startedAt! >= b.real) queue = finishService(queue, head.bookingId);
      }
      const onBreak = d.breaks.some((br) => now >= br.start && now < br.end);
      if (queue[0]?.status !== 'in_service' && !onBreak && now >= d.workStart) {
        const called = queue.find((e) => e.status === 'called');
        if (called) {
          const b = bookings.get(called.bookingId)!;
          const slotStart = projectQueue(d, queue, now).find((s) => s.bookingId === called.bookingId)!.start;
          if (slotStart <= now) {
            if (b.late && !called.postponeUsed) {
              queue = postpone(queue, called.bookingId, 1);
              b.late = rand() < 0.3;
              const next = selectToCall(queue, projectQueue(d, queue, now), now, cfg.leadTime, { immediate: true });
              if (next) queue = markCalled(queue, next);
            } else if (b.late) {
              queue = remove(queue, called.bookingId);
              b.noShow = true;
            } else {
              queue = startService(queue, called.bookingId, now).queue;
              b.startedAt = now;
            }
          }
        }
      }
      const slots = projectQueue(d, queue, now);
      const toCall = selectToCall(queue, slots, now, cfg.leadTime);
      if (toCall) queue = markCalled(queue, toCall);
      for (const s of slots) {
        const b = bookings.get(s.bookingId)!;
        if (b.startedAt === undefined && needsNotification(b.lastCommunicated, s.start, cfg.policy)) {
          b.notifications++;
          b.lastCommunicated = s.start;
        }
      }
      queues.set(d.barberId, queue);
    }
  }

  const all = [...bookings.values()];
  const served = all.filter((b) => b.startedAt !== undefined);
  const errs = served.map((b) => Math.abs(b.startedAt! - b.firstEta) / MINUTE).sort((a, b) => a - b);
  const mean = errs.reduce((a, b) => a + b, 0) / Math.max(1, errs.length);
  const dayLen = close - open;
  return {
    requests,
    accepted: all.length,
    refused,
    served: served.length,
    cancelled: all.filter((b) => b.cancelled).length,
    noShows: all.filter((b) => b.noShow).length,
    meanEtaErrorMin: Math.round(mean * 10) / 10,
    p90EtaErrorMin: Math.round((errs[Math.floor(errs.length * 0.9)] ?? 0) * 10) / 10,
    notifiedShare: Math.round((100 * served.filter((b) => b.notifications > 0).length) / Math.max(1, served.length)) / 100,
    utilization: Math.round((100 * [...busy.values()].reduce((a, b) => a + b, 0)) / (dayLen * cfg.barbers)) / 100,
  };
}

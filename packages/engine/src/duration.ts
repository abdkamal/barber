import { HOUR, MINUTE, type Ms } from './types.js';

/**
 * ق11 / design §5.10 — durations are learned per (barber, set of services
 * actually performed), measured only from the barber's "start" and "end" taps.
 * Initial formula; constants are tunable after real use.
 */
export interface DurationParams {
  /** Weight of the reference (base, or the barber's median) against the barber's history. */
  barberPriorWeight: number;
  /** Weight of the barber estimate against this customer's own history. */
  customerPriorWeight: number;
  barberWindow: number;
  customerWindow: number;
  /** After this many barber samples, outliers are judged against the barber's median, not the base. */
  medianAfter: number;
  /** Samples outside [min, max] × reference are discarded as bad taps. */
  outlierMin: number;
  outlierMax: number;
  /** Absolute sanity bounds. */
  absMin: Ms;
  absMax: Ms;
}

export const DEFAULT_DURATION_PARAMS: DurationParams = {
  barberPriorWeight: 3,
  customerPriorWeight: 2,
  barberWindow: 20,
  customerWindow: 5,
  medianAfter: 10,
  outlierMin: 0.3,
  outlierMax: 3,
  absMin: 2 * MINUTE,
  absMax: 4 * HOUR,
};

/** Canonical key for a set of services, e.g. "beard+hair". */
export function serviceSetKey(serviceIds: readonly string[]): string {
  return [...new Set(serviceIds)].sort().join('+');
}

/** Measured duration of a finished service, or null if the taps are unusable (e.g. approximate offline time). */
export function measuredDuration(start: Ms, end: Ms, opts: { approximate?: boolean } = {}): Ms | null {
  if (opts.approximate) return null;
  return end > start ? end - start : null;
}

function median(xs: readonly Ms[]): Ms {
  const s = [...xs].sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

function plausible(d: Ms, ref: Ms, p: DurationParams): boolean {
  return d >= p.absMin && d <= p.absMax && d >= ref * p.outlierMin && d <= ref * p.outlierMax;
}

/** The reference a barber's samples are judged against: base, then his own median once there is enough history. */
export function barberReference(baseDuration: Ms, barberSamples: readonly Ms[], p: DurationParams = DEFAULT_DURATION_PARAMS): Ms {
  const recent = barberSamples.slice(-p.barberWindow).filter((d) => d >= p.absMin && d <= p.absMax);
  return recent.length >= p.medianAfter ? median(recent) : baseDuration;
}

/**
 * @param baseDuration     configured duration for the service set
 * @param barberSamples    this barber's past durations for the set, oldest first
 * @param customerSamples  this customer's past durations for the set at this barber, oldest first
 */
export function estimateDuration(
  baseDuration: Ms,
  barberSamples: readonly Ms[],
  customerSamples: readonly Ms[],
  p: DurationParams = DEFAULT_DURATION_PARAMS,
): Ms {
  const ref = barberReference(baseDuration, barberSamples, p);
  const barberEst = shrink(ref, barberSamples, p.barberWindow, p.barberPriorWeight, ref, p);
  const est = shrink(barberEst, customerSamples, p.customerWindow, p.customerPriorWeight, barberEst, p);
  return Math.max(MINUTE, Math.round(est / MINUTE) * MINUTE);
}

/** Mean of recent plausible samples, pulled toward `prior` with weight `k`. */
function shrink(prior: Ms, samples: readonly Ms[], window: number, k: number, ref: Ms, p: DurationParams): Ms {
  const kept = samples.slice(-window).filter((d) => plausible(d, ref, p));
  const sum = kept.reduce((a, b) => a + b, 0);
  return (sum + k * prior) / (kept.length + k);
}

/** Design §5.10: warn the manager when most recent samples are rejected — the base duration is probably wrong. */
export function baseDurationSuspect(baseDuration: Ms, barberSamples: readonly Ms[], p: DurationParams = DEFAULT_DURATION_PARAMS): boolean {
  const recent = barberSamples.slice(-10);
  if (recent.length < 5) return false;
  const rejected = recent.filter((d) => !plausible(d, baseDuration, p)).length;
  return rejected / recent.length >= 0.5;
}

/** Pure overlap checks for breaks (schedules controller validation). No DB, easy to unit test. */

function toMinutes(hms: string): number {
  const [h, m] = hms.split(':').map(Number);
  return h! * 60 + m!;
}

/** Splits a possibly midnight-crossing [start,end) time-of-day range into 1 or 2 linear ranges. */
function splitRange(startTime: string, endTime: string): Array<[number, number]> {
  const s = toMinutes(startTime);
  const e = toMinutes(endTime);
  if (e > s) return [[s, e]];
  // crosses midnight (design §2/ق30 convention: end <= start): [s,1440) and [0,e)
  return [
    [s, 1440],
    [0, e],
  ];
}

function rangesOverlap(a: [number, number], b: [number, number]): boolean {
  return a[0] < b[1] && b[0] < a[1];
}

/** True if two recurring (daily) time-of-day breaks overlap, honouring midnight crossing. */
export function recurringBreaksOverlap(aStart: string, aEnd: string, bStart: string, bEnd: string): boolean {
  const as = splitRange(aStart, aEnd);
  const bs = splitRange(bStart, bEnd);
  return as.some((a) => bs.some((b) => rangesOverlap(a, b)));
}

/** True if two dated breaks (absolute instants) overlap. */
export function datedBreaksOverlap(aStart: Date, aEnd: Date, bStart: Date, bEnd: Date): boolean {
  return aStart < bEnd && bStart < aEnd;
}

/**
 * Salon-timezone helpers (no external tz library: Intl only). Pure functions.
 *
 * Business day (ق30): a barber's day runs from his opening to his closing time in the salon's
 * timezone and may cross midnight (closes_at <= opens_at). The day is identified by the local
 * date on which it opens (`work_date`).
 */

export const MIN = 60_000;

const dtfCache = new Map<string, Intl.DateTimeFormat>();
function dtf(tz: string): Intl.DateTimeFormat {
  let f = dtfCache.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', {
      timeZone: tz,
      hourCycle: 'h23',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
    dtfCache.set(tz, f);
  }
  return f;
}

interface Wall {
  y: number;
  m: number; // 1-12
  d: number;
  h: number;
  mi: number;
  s: number;
}

export function wallClock(instant: number, tz: string): Wall {
  const parts = dtf(tz).formatToParts(new Date(instant));
  const get = (t: string) => Number(parts.find((p) => p.type === t)!.value);
  return { y: get('year'), m: get('month'), d: get('day'), h: get('hour') % 24, mi: get('minute'), s: get('second') };
}

/** Offset (ms) of the timezone at an instant: local wall time − UTC. */
export function tzOffset(instant: number, tz: string): number {
  const w = wallClock(instant, tz);
  const asUtc = Date.UTC(w.y, w.m - 1, w.d, w.h, w.mi, w.s);
  return asUtc - Math.floor(instant / 1000) * 1000;
}

/** Local date (YYYY-MM-DD) of an instant in the timezone. */
export function localDate(instant: number, tz: string): string {
  const w = wallClock(instant, tz);
  return `${w.y}-${pad(w.m)}-${pad(w.d)}`;
}

function pad(n: number): string {
  return String(n).padStart(2, '0');
}

export function addDays(date: string, days: number): string {
  const [y, m, d] = date.split('-').map(Number) as [number, number, number];
  const t = new Date(Date.UTC(y, m - 1, d + days));
  return `${t.getUTCFullYear()}-${pad(t.getUTCMonth() + 1)}-${pad(t.getUTCDate())}`;
}

/** 0 = Sunday … 6 = Saturday, like work_schedules.weekday. */
export function weekday(date: string): number {
  const [y, m, d] = date.split('-').map(Number) as [number, number, number];
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
}

/** Parses 'HH:MM[:SS]' into seconds since midnight. */
export function timeOfDaySec(t: string): number {
  const [h, m, s] = t.split(':').map(Number);
  return (h ?? 0) * 3600 + (m ?? 0) * 60 + (s ?? 0);
}

/**
 * The UTC instant of a local wall-clock time on a local date. For times skipped by a DST jump the
 * result lands just after the gap; ambiguous times resolve to the first occurrence.
 */
export function localToUtc(date: string, time: string, tz: string): number {
  const [y, m, d] = date.split('-').map(Number) as [number, number, number];
  const sec = timeOfDaySec(time);
  const wall = Date.UTC(y, m - 1, d) + sec * 1000;
  let guess = wall - tzOffset(wall, tz);
  const off2 = tzOffset(guess, tz);
  guess = wall - off2;
  return guess;
}

export interface ScheduleRow {
  weekday: number;
  opens_at: string;
  closes_at: string;
}

export interface Shift {
  /** Local date on which the shift opens. */
  workDate: string;
  workStart: number;
  workEnd: number;
}

/** The absolute shift of a schedule on a local date (closing ≤ opening ⇒ ends the next day, ق30). */
export function shiftOn(date: string, schedules: readonly ScheduleRow[], tz: string): Shift | null {
  const s = schedules.find((r) => r.weekday === weekday(date));
  if (!s) return null;
  const crosses = timeOfDaySec(s.closes_at) <= timeOfDaySec(s.opens_at);
  return {
    workDate: date,
    workStart: localToUtc(date, s.opens_at, tz),
    workEnd: localToUtc(crosses ? addDays(date, 1) : date, s.closes_at, tz),
  };
}

/**
 * The barber's current business day at `now`: a shift still running (possibly yesterday's, across
 * midnight) or the next one that opens within `lookaheadMs` (booking opens before opening, §5.11).
 * Returns null when no shift is running or about to open.
 */
export function currentShift(schedules: readonly ScheduleRow[], tz: string, now: number, lookaheadMs: number): Shift | null {
  const today = localDate(now, tz);
  for (const date of [addDays(today, -1), today, addDays(today, 1)]) {
    const s = shiftOn(date, schedules, tz);
    if (s && now < s.workEnd && now >= s.workStart - lookaheadMs) return s;
  }
  return null;
}

/**
 * Converts a (daily, salon-local) recurring break into absolute time within a shift. A break whose
 * local start is before the shift's opening time on a shift that crosses midnight belongs to the
 * following calendar day.
 */
export function dailyBreakInShift(shift: Shift, start: string, end: string, tz: string, opensAt: string): { start: number; end: number } {
  const opensSec = timeOfDaySec(opensAt);
  const startDate = timeOfDaySec(start) < opensSec ? addDays(shift.workDate, 1) : shift.workDate;
  const s = localToUtc(startDate, start, tz);
  let e = localToUtc(startDate, end, tz);
  if (e <= s) e = localToUtc(addDays(startDate, 1), end, tz);
  return { start: s, end: e };
}

const arTime = new Map<string, Intl.DateTimeFormat>();
/** Arabic clock time for messages, e.g. «٤:٣٠ م». */
export function formatArabicTime(instant: number, tz: string): string {
  let f = arTime.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat('ar', { timeZone: tz, hour: 'numeric', minute: '2-digit', hour12: true });
    arTime.set(tz, f);
  }
  return f.format(new Date(instant));
}

/** Arabic duration for messages, e.g. «٤٠ دقيقة» / «ساعة و١٠ دقائق». */
export function formatArabicDuration(ms: number): string {
  const total = Math.max(1, Math.round(Math.abs(ms) / MIN));
  const nf = new Intl.NumberFormat('ar');
  const h = Math.floor(total / 60);
  const m = total % 60;
  const mins = (n: number) => (n === 1 ? 'دقيقة' : n === 2 ? 'دقيقتين' : n <= 10 ? `${nf.format(n)} دقائق` : `${nf.format(n)} دقيقة`);
  const hours = (n: number) => (n === 1 ? 'ساعة' : n === 2 ? 'ساعتين' : n <= 10 ? `${nf.format(n)} ساعات` : `${nf.format(n)} ساعة`);
  if (!h) return mins(m);
  if (!m) return hours(h);
  return `${hours(h)} و${mins(m)}`;
}

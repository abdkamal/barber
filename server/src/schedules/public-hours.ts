/**
 * Pure helpers to derive the public "hours per weekday" + "open now" flag from work_schedules
 * (design §2/§10, public salon profile). No DB access — feed it rows already queried.
 *
 * Integration note (see final report): the public profile endpoint `GET /v1/salons/{code}` lives
 * in `provisioning/salons.controller.ts`, which is outside this milestone's edit scope. Whoever
 * owns that file wires these two functions in; the SQL needed is one extra query:
 *   SELECT staff_id, weekday, opens_at, closes_at FROM work_schedules
 */

export interface ScheduleRow {
  staff_id: string | null; // null = salon-wide default
  weekday: number; // 0 = Sunday
  opens_at: string; // 'HH:MM:SS'
  closes_at: string;
}

export interface WeekdayHours {
  weekday: number;
  opensAt: string; // 'HH:MM'
  closesAt: string; // 'HH:MM'
  crossesMidnight: boolean;
}

/** One row per weekday (0..6): the salon-wide hours, i.e. the default row, falling back to the
 * earliest-opening / latest-closing barber hours for that weekday when there is no explicit
 * default (ق30: closesAt <= opensAt means the shift crosses midnight). Returns [] for weekdays
 * with no hours defined at all (closed). */
export function publicWeeklyHours(rows: ScheduleRow[]): WeekdayHours[] {
  const out: WeekdayHours[] = [];
  for (let weekday = 0; weekday <= 6; weekday++) {
    const forDay = rows.filter((r) => r.weekday === weekday);
    const def = forDay.find((r) => r.staff_id === null);
    const chosen = def ?? forDay[0];
    if (!chosen) continue;
    out.push({
      weekday,
      opensAt: chosen.opens_at.slice(0, 5),
      closesAt: chosen.closes_at.slice(0, 5),
      crossesMidnight: chosen.closes_at <= chosen.opens_at,
    });
  }
  return out;
}

/** True if `now` (any Date) falls within the salon's hours for its current business day, in `timezone`. */
export function isOpenNow(rows: ScheduleRow[], timezone: string, now = new Date()): boolean {
  const hours = publicWeeklyHours(rows);
  if (hours.length === 0) return false;
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: timezone,
    weekday: 'short',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(now);
  const weekdayShort = parts.find((p) => p.type === 'weekday')!.value; // 'Sun'..'Sat'
  const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const todayIdx = WEEKDAYS.indexOf(weekdayShort);
  const hh = Number(parts.find((p) => p.type === 'hour')!.value);
  const mm = Number(parts.find((p) => p.type === 'minute')!.value);
  const nowMin = hh * 60 + mm;

  const check = (idx: number, minutesIntoThatDay: number): boolean => {
    const h = hours.find((x) => x.weekday === idx);
    if (!h) return false;
    const [oh, om] = h.opensAt.split(':').map(Number);
    const [ch, cm] = h.closesAt.split(':').map(Number);
    const openMin = oh! * 60 + om!;
    const closeMin = ch! * 60 + cm!;
    if (!h.crossesMidnight) return minutesIntoThatDay >= openMin && minutesIntoThatDay < closeMin;
    // Crosses midnight: open from openMin..1440 today, and 0..closeMin "tomorrow" (i.e. still today's business day).
    return minutesIntoThatDay >= openMin || minutesIntoThatDay < closeMin;
  };

  if (check(todayIdx, nowMin)) return true;
  // Also check yesterday's shift, in case it crossed into today before closing.
  const yesterdayIdx = (todayIdx + 6) % 7;
  const yesterday = hours.find((x) => x.weekday === yesterdayIdx);
  if (yesterday?.crossesMidnight) {
    const [ch, cm] = yesterday.closesAt.split(':').map(Number);
    if (nowMin < ch! * 60 + cm!) return true;
  }
  return false;
}

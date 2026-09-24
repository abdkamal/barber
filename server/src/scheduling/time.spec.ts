import { MINUTE, serviceSetKey } from '@saloni/engine';
import { addDays, currentShift, dailyBreakInShift, localDate, localToUtc, shiftOn, tzOffset, weekday } from './time';

describe('salon time helpers', () => {
  it('uses the engine from the workspace', () => {
    expect(MINUTE).toBe(60_000);
    expect(serviceSetKey(['b', 'a', 'a'])).toBe('a+b');
  });

  it('converts local wall time to UTC (fixed offset and DST zones)', () => {
    expect(new Date(localToUtc('2026-09-24', '09:00', 'Asia/Riyadh')).toISOString()).toBe('2026-09-24T06:00:00.000Z');
    expect(tzOffset(Date.UTC(2026, 8, 24), 'Asia/Riyadh')).toBe(3 * 3600_000);
    // Europe/Berlin: CEST (UTC+2) in September, CET (UTC+1) in December.
    expect(new Date(localToUtc('2026-09-24', '10:30', 'Europe/Berlin')).toISOString()).toBe('2026-09-24T08:30:00.000Z');
    expect(new Date(localToUtc('2026-12-24', '10:30', 'Europe/Berlin')).toISOString()).toBe('2026-12-24T09:30:00.000Z');
  });

  it('local dates and weekdays', () => {
    expect(localDate(Date.parse('2026-09-24T22:30:00Z'), 'Asia/Riyadh')).toBe('2026-09-25');
    expect(weekday('2026-09-24')).toBe(4); // Thursday
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01');
    expect(addDays('2026-03-01', -1)).toBe('2026-02-28');
  });

  const allWeek = (opens: string, closes: string) => [0, 1, 2, 3, 4, 5, 6].map((weekday) => ({ weekday, opens_at: opens, closes_at: closes }));

  it('a shift that crosses midnight belongs to the day it opens (ق30)', () => {
    const tz = 'Asia/Riyadh';
    const s = shiftOn('2026-09-24', allWeek('16:00:00', '02:00:00'), tz)!;
    expect(new Date(s.workStart).toISOString()).toBe('2026-09-24T13:00:00.000Z');
    expect(new Date(s.workEnd).toISOString()).toBe('2026-09-24T23:00:00.000Z');
    // 01:00 local on the 25th is still the 24th's business day.
    const at = Date.parse('2026-09-24T22:00:00Z');
    expect(currentShift(allWeek('16:00:00', '02:00:00'), tz, at, 60 * 60_000)!.workDate).toBe('2026-09-24');
  });

  it('booking opens an hour before opening; nothing after closing', () => {
    const tz = 'Asia/Riyadh';
    const sched = allWeek('09:00:00', '21:00:00');
    expect(currentShift(sched, tz, Date.parse('2026-09-24T05:30:00Z'), 3600_000)?.workDate).toBe('2026-09-24'); // 08:30
    expect(currentShift(sched, tz, Date.parse('2026-09-24T04:30:00Z'), 3600_000)).toBeNull(); // 07:30
    expect(currentShift(sched, tz, Date.parse('2026-09-24T18:30:00Z'), 3600_000)).toBeNull(); // 21:30
    expect(currentShift([{ weekday: 5, opens_at: '09:00', closes_at: '21:00' }], tz, Date.parse('2026-09-24T08:00:00Z'), 0)).toBeNull();
  });

  it('daily breaks map into the shift, including after midnight', () => {
    const tz = 'Asia/Riyadh';
    const shift = shiftOn('2026-09-24', allWeek('16:00:00', '02:00:00'), tz)!;
    const b = dailyBreakInShift(shift, '00:30:00', '01:00:00', tz, '16:00:00');
    expect(new Date(b.start).toISOString()).toBe('2026-09-24T21:30:00.000Z');
    const c = dailyBreakInShift(shift, '19:00:00', '19:30:00', tz, '16:00:00');
    expect(new Date(c.start).toISOString()).toBe('2026-09-24T16:00:00.000Z');
    expect(c.end - c.start).toBe(30 * 60_000);
  });
});

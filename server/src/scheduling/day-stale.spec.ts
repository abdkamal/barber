import { MINUTE } from '@saloni/engine';
import { type DayWindow, isStaleDay, shiftOrDay, staleAt } from './day';

const tz = 'Asia/Riyadh';
const allWeek = (opens: string, closes: string) => [0, 1, 2, 3, 4, 5, 6].map((weekday) => ({ weekday, opens_at: opens, closes_at: closes }));
const t = (iso: string) => Date.parse(iso);
const HOUR = 60 * MINUTE;
/** A grace long enough never to be the binding limit in the "next day" cases. */
const win = (lookaheadMin: number, graceH = 12): DayWindow => ({ lookaheadMs: lookaheadMin * MINUTE, graceMs: graceH * HOUR });

describe('operational day / stale business days (review C1)', () => {
  const sch = allWeek('09:00:00', '23:00:00'); // 06:00–20:00 UTC

  it('a day that just closed is not stale — customers may still be served after closing (ق24)', () => {
    expect(isStaleDay(sch, tz, '2026-03-05', t('2026-03-05T19:59:00Z'), win(60))).toBe(false); // before closing
    expect(isStaleDay(sch, tz, '2026-03-05', t('2026-03-05T21:30:00Z'), win(60))).toBe(false); // 00:30 local
  });

  it('it becomes stale when the next business day opens for booking', () => {
    expect(isStaleDay(sch, tz, '2026-03-05', t('2026-03-06T04:59:00Z'), win(60))).toBe(false); // 07:59
    expect(isStaleDay(sch, tz, '2026-03-05', t('2026-03-06T05:00:00Z'), win(60))).toBe(true); // 08:00 = 09:00 − 60
  });

  it('shifts crossing midnight (ق30) and days without a schedule', () => {
    const night = allWeek('16:00:00', '02:00:00');
    expect(isStaleDay(night, tz, '2026-03-05', t('2026-03-06T00:00:00Z'), win(0))).toBe(false); // 03:00 local, after closing
    expect(isStaleDay(night, tz, '2026-03-05', t('2026-03-06T13:00:00Z'), win(0))).toBe(true); // next day opens 16:00
    const none = shiftOrDay([], tz, '2026-03-05');
    expect(new Date(none.workStart).toISOString()).toBe('2026-03-04T21:00:00.000Z');
    expect(isStaleDay([], tz, '2026-03-05', none.workEnd + 11 * HOUR, win(0))).toBe(false);
    expect(isStaleDay([], tz, '2026-03-05', none.workEnd + 12 * HOUR, win(0))).toBe(true);
  });
});

describe('stale day is bounded by the grace after closing (round 2, item 1)', () => {
  // Thursday 2026-03-05, 09:00–12:00 local (06:00–09:00 UTC); default grace 6 h → 18:00 local.
  const grace6: DayWindow = { lookaheadMs: 60 * MINUTE, graceMs: 6 * HOUR };

  it('salon closed on Fridays: Thursday is stale 6 h after closing, not on Saturday morning', () => {
    const noFriday = [0, 1, 2, 3, 4, 6].map((weekday) => ({ weekday, opens_at: '09:00:00', closes_at: '12:00:00' }));
    expect(isStaleDay(noFriday, tz, '2026-03-05', t('2026-03-05T14:59:00Z'), grace6)).toBe(false); // 17:59
    expect(isStaleDay(noFriday, tz, '2026-03-05', t('2026-03-05T15:00:00Z'), grace6)).toBe(true); // 18:00
    expect(staleAt(noFriday, tz, '2026-03-05', grace6)).toBe(t('2026-03-05T15:00:00Z'));
  });

  it('a barber working one day a week: stale after the grace, not six days later', () => {
    const thursdays = [{ weekday: 4, opens_at: '09:00:00', closes_at: '12:00:00' }];
    expect(isStaleDay(thursdays, tz, '2026-03-05', t('2026-03-05T15:00:00Z'), grace6)).toBe(true);
    expect(isStaleDay(thursdays, tz, '2026-03-05', t('2026-03-05T11:00:00Z'), grace6)).toBe(false); // 14:00, still ق24 time
  });

  it('the earlier limit wins: a next shift opening before the grace ends makes the day stale first', () => {
    const late = allWeek('20:00:00', '23:00:00'); // closes 23:00 local, grace 12 h → 11:00; next window 19:00 → 11:00 wins
    expect(staleAt(late, tz, '2026-03-05', { lookaheadMs: 60 * MINUTE, graceMs: 12 * HOUR })).toBe(t('2026-03-06T08:00:00Z'));
    const early = allWeek('09:00:00', '23:00:00'); // grace 12 h → 11:00 next day; next window 08:00 wins
    expect(staleAt(early, tz, '2026-03-05', { lookaheadMs: 60 * MINUTE, graceMs: 12 * HOUR })).toBe(t('2026-03-06T05:00:00Z'));
  });
});

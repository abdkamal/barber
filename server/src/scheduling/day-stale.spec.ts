import { MINUTE } from '@saloni/engine';
import { isStaleDay, shiftOrDay } from './day';

const tz = 'Asia/Riyadh';
const allWeek = (opens: string, closes: string) => [0, 1, 2, 3, 4, 5, 6].map((weekday) => ({ weekday, opens_at: opens, closes_at: closes }));
const t = (iso: string) => Date.parse(iso);

describe('operational day / stale business days (review C1)', () => {
  const sch = allWeek('09:00:00', '23:00:00'); // 06:00–20:00 UTC

  it('a day that just closed is not stale — customers may still be served after closing (ق24)', () => {
    expect(isStaleDay(sch, tz, '2026-03-05', t('2026-03-05T19:59:00Z'), 60 * MINUTE)).toBe(false); // before closing
    expect(isStaleDay(sch, tz, '2026-03-05', t('2026-03-05T21:30:00Z'), 60 * MINUTE)).toBe(false); // 00:30 local
  });

  it('it becomes stale when the next business day opens for booking', () => {
    expect(isStaleDay(sch, tz, '2026-03-05', t('2026-03-06T04:59:00Z'), 60 * MINUTE)).toBe(false); // 07:59
    expect(isStaleDay(sch, tz, '2026-03-05', t('2026-03-06T05:00:00Z'), 60 * MINUTE)).toBe(true); // 08:00 = 09:00 − 60
  });

  it('shifts crossing midnight (ق30) and days without a schedule', () => {
    const night = allWeek('16:00:00', '02:00:00');
    expect(isStaleDay(night, tz, '2026-03-05', t('2026-03-06T00:00:00Z'), 0)).toBe(false); // 03:00 local, after closing
    expect(isStaleDay(night, tz, '2026-03-05', t('2026-03-06T13:00:00Z'), 0)).toBe(true); // next day opens 16:00
    const none = shiftOrDay([], tz, '2026-03-05');
    expect(new Date(none.workStart).toISOString()).toBe('2026-03-04T21:00:00.000Z');
    expect(isStaleDay([], tz, '2026-03-05', none.workEnd + 23 * 60 * MINUTE, 0)).toBe(false);
    expect(isStaleDay([], tz, '2026-03-05', none.workEnd + 24 * 60 * MINUTE, 0)).toBe(true);
  });
});

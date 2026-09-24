import { isOpenNow, publicWeeklyHours, ScheduleRow } from './public-hours';

const TZ = 'Asia/Riyadh';

describe('publicWeeklyHours', () => {
  it('prefers the salon default over a barber-only row for the same weekday', () => {
    const rows: ScheduleRow[] = [
      { staff_id: null, weekday: 0, opens_at: '09:00:00', closes_at: '22:00:00' },
      { staff_id: 'barber-1', weekday: 0, opens_at: '10:00:00', closes_at: '20:00:00' },
    ];
    const hours = publicWeeklyHours(rows);
    expect(hours).toEqual([{ weekday: 0, opensAt: '09:00', closesAt: '22:00', crossesMidnight: false }]);
  });

  it('falls back to a barber row when there is no salon default', () => {
    const rows: ScheduleRow[] = [{ staff_id: 'barber-1', weekday: 3, opens_at: '11:00:00', closes_at: '23:00:00' }];
    expect(publicWeeklyHours(rows)[0]!.opensAt).toBe('11:00');
  });

  it('flags a midnight-crossing shift', () => {
    const rows: ScheduleRow[] = [{ staff_id: null, weekday: 5, opens_at: '20:00:00', closes_at: '02:00:00' }];
    expect(publicWeeklyHours(rows)[0]!.crossesMidnight).toBe(true);
  });

  it('returns nothing for a weekday with no hours at all', () => {
    expect(publicWeeklyHours([])).toEqual([]);
  });
});

describe('isOpenNow', () => {
  it('is true inside a normal same-day shift', () => {
    // 2026-09-24 is a Thursday; Riyadh has no DST.
    const rows: ScheduleRow[] = [{ staff_id: null, weekday: 4, opens_at: '09:00:00', closes_at: '22:00:00' }];
    const now = new Date('2026-09-24T10:00:00Z'); // 13:00 Riyadh
    expect(isOpenNow(rows, TZ, now)).toBe(true);
  });

  it('is false before opening and after closing', () => {
    const rows: ScheduleRow[] = [{ staff_id: null, weekday: 4, opens_at: '09:00:00', closes_at: '22:00:00' }];
    expect(isOpenNow(rows, TZ, new Date('2026-09-24T04:00:00Z'))).toBe(false); // 07:00 Riyadh
    expect(isOpenNow(rows, TZ, new Date('2026-09-24T20:00:00Z'))).toBe(false); // 23:00 Riyadh
  });

  it('stays open past midnight for a crossing shift, and recognises it from "yesterday"', () => {
    // Thursday 20:00 -> Friday 02:00 (weekday 4 crossing into weekday 5).
    const rows: ScheduleRow[] = [{ staff_id: null, weekday: 4, opens_at: '20:00:00', closes_at: '02:00:00' }];
    // 2026-09-25T00:30 Riyadh = 2026-09-24T21:30Z, still Thursday 23:30 local... use explicit past-midnight instant.
    const afterMidnightRiyadh = new Date('2026-09-24T22:30:00Z'); // 2026-09-25 01:30 Riyadh (Friday, weekday 5)
    expect(isOpenNow(rows, TZ, afterMidnightRiyadh)).toBe(true);
  });

  it('is closed when there are no hours defined', () => {
    expect(isOpenNow([], TZ)).toBe(false);
  });
});

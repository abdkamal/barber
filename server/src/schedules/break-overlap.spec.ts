import { datedBreaksOverlap, recurringBreaksOverlap } from './break-overlap';

describe('recurringBreaksOverlap', () => {
  it('detects a simple overlap', () => {
    expect(recurringBreaksOverlap('13:00', '13:30', '13:15', '13:45')).toBe(true);
  });
  it('detects adjacent (non-overlapping) ranges as not overlapping', () => {
    expect(recurringBreaksOverlap('13:00', '13:30', '13:30', '14:00')).toBe(false);
  });
  it('detects no overlap for disjoint ranges', () => {
    expect(recurringBreaksOverlap('09:00', '09:30', '13:00', '13:30')).toBe(false);
  });
  it('handles a midnight-crossing break overlapping a late-evening one', () => {
    // 22:00 -> 02:00 crosses midnight; 23:00 -> 23:30 falls inside it.
    expect(recurringBreaksOverlap('22:00', '02:00', '23:00', '23:30')).toBe(true);
  });
  it('handles two midnight-crossing breaks that do not actually overlap', () => {
    expect(recurringBreaksOverlap('22:00', '01:00', '01:30', '05:00')).toBe(false);
  });
});

describe('datedBreaksOverlap', () => {
  it('detects overlap of absolute instants', () => {
    const a1 = new Date('2026-09-24T10:00:00Z');
    const a2 = new Date('2026-09-24T10:30:00Z');
    const b1 = new Date('2026-09-24T10:15:00Z');
    const b2 = new Date('2026-09-24T10:45:00Z');
    expect(datedBreaksOverlap(a1, a2, b1, b2)).toBe(true);
  });
  it('detects no overlap', () => {
    const a1 = new Date('2026-09-24T10:00:00Z');
    const a2 = new Date('2026-09-24T10:30:00Z');
    const b1 = new Date('2026-09-24T11:00:00Z');
    const b2 = new Date('2026-09-24T11:30:00Z');
    expect(datedBreaksOverlap(a1, a2, b1, b2)).toBe(false);
  });
});

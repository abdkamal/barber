import { AFTER_SUSPENSION, recoveryOutcomes, recoveryTimeCheck } from './sync.service';

const MIN = 60_000;
const S = Date.parse('2026-03-05T08:00:00Z');

describe('ق40 recovery — suspension boundary', () => {
  it('accepts only device times strictly before the suspension', () => {
    expect(recoveryTimeCheck(S - 1, S, S + 60 * MIN)).toBeNull();
    expect(recoveryTimeCheck(S - 30 * MIN, S, S + 60 * MIN)).toBeNull();
    expect(recoveryTimeCheck(S, S, S + 60 * MIN)).toBe(AFTER_SUSPENSION);
    expect(recoveryTimeCheck(S + 1, S, S + 60 * MIN)).toBe(AFTER_SUSPENSION);
  });

  it('measures the 48 h age limit from the suspension (the device could not send after it)', () => {
    const now = S + 5 * 24 * 60 * MIN; // handed to the manager five days later
    expect(recoveryTimeCheck(S - 47 * 60 * MIN, S, now)).toBeNull();
    expect(recoveryTimeCheck(S - 49 * 60 * MIN, S, now)).toBe('EVENT_TOO_OLD');
  });
});

describe('ق40 recovery — per-event results', () => {
  it('maps applied / duplicate / after-suspension / invalid and counts them', () => {
    const prior = new Map([
      ['d-applied', { result: 'applied', reason: null }],
      ['d-late', { result: 'rejected', reason: AFTER_SUSPENSION }],
      ['d-bad', { result: 'rejected', reason: 'NOT_IN_SERVICE' }],
    ]);
    const out = recoveryOutcomes(
      [
        { eventId: 'a', result: 'applied' },
        { eventId: 'a2', result: 'applied', reason: 'AMOUNT_DIFFERS_FROM_PRICE' },
        { eventId: 'late', result: 'rejected', reason: AFTER_SUSPENSION },
        { eventId: 'bad', result: 'rejected', reason: 'BOOKING_NOT_FOUND' },
        { eventId: 'd-applied', result: 'duplicate', reason: 'applied' },
        { eventId: 'd-late', result: 'duplicate', reason: 'rejected' },
        { eventId: 'd-bad', result: 'duplicate', reason: 'rejected' },
        { eventId: 'race', result: 'duplicate' },
      ],
      prior,
    );
    expect(out.results).toEqual([
      { eventId: 'a', result: 'applied' },
      { eventId: 'a2', result: 'applied', reason: 'AMOUNT_DIFFERS_FROM_PRICE' },
      { eventId: 'late', result: 'rejected_after_suspension', reason: AFTER_SUSPENSION },
      { eventId: 'bad', result: 'rejected_invalid', reason: 'BOOKING_NOT_FOUND' },
      { eventId: 'd-applied', result: 'duplicate' },
      { eventId: 'd-late', result: 'rejected_after_suspension', reason: AFTER_SUSPENSION },
      { eventId: 'd-bad', result: 'rejected_invalid', reason: 'NOT_IN_SERVICE' },
      { eventId: 'race', result: 'duplicate' },
    ]);
    expect(out.summary).toEqual({ applied: 2, duplicate: 2, rejectedAfterSuspension: 2, rejectedInvalid: 2 });
  });
});

import { backoffDelayMs } from './backoff';

describe('backoffDelayMs', () => {
  const o = { free: 3, baseMs: 1000, maxMs: 15 * 60_000 };
  it('allows the first free attempts without delay', () => {
    expect([0, 1, 2, 3].map((n) => backoffDelayMs(n, o))).toEqual([0, 0, 0, 0]);
  });
  it('doubles after that', () => {
    expect([4, 5, 6, 7].map((n) => backoffDelayMs(n, o))).toEqual([1000, 2000, 4000, 8000]);
  });
  it('is capped (never a permanent lockout)', () => {
    expect(backoffDelayMs(20, o)).toBe(o.maxMs);
    expect(backoffDelayMs(10_000, o)).toBe(o.maxMs);
  });
});

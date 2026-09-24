import { RateLimiter } from './rate-limiter';

describe('RateLimiter', () => {
  it('allows up to the limit per window and reports retry-after', () => {
    let now = 1_000_000;
    const rl = new RateLimiter(() => now);
    const rule = { limit: 3, windowMs: 10_000 };
    expect([rl.hit('k', rule), rl.hit('k', rule), rl.hit('k', rule)]).toEqual([0, 0, 0]);
    expect(rl.hit('k', rule)).toBe(10);
    expect(rl.hit('other', rule)).toBe(0);
    now += 4_000;
    expect(rl.hit('k', rule)).toBe(6);
    now += 6_000;
    expect(rl.hit('k', rule)).toBe(0);
  });
});

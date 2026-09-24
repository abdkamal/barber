import { describe, expect, it } from 'vitest';
import { DEFAULT_SIM, simulate } from '../src/sim/simulate.js';

describe('work-day simulator', () => {
  it('runs a full day through the engine without breaking queue invariants', () => {
    const r = simulate({ ...DEFAULT_SIM, seed: 7 });
    expect(r.requests).toBeGreaterThan(50);
    expect(r.accepted + r.refused).toBe(r.requests);
    expect(r.served).toBeGreaterThan(0);
    expect(r.served + r.cancelled + r.noShows).toBeLessThanOrEqual(r.accepted);
    expect(r.utilization).toBeGreaterThan(0);
    expect(r.utilization).toBeLessThanOrEqual(1);
  });

  it('is deterministic for a seed', () => {
    expect(simulate({ ...DEFAULT_SIM, seed: 3 })).toEqual(simulate({ ...DEFAULT_SIM, seed: 3 }));
  });
});

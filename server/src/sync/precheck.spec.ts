import { precheckEvent } from './sync.service';

const ev = (type: string, payload: Record<string, unknown> = {}, bookingId: string | null = '7f0c7a3e-3b1b-4f0e-9a51-2a3c1b0e9d11') => ({
  id: '0b6f4f3a-1a2b-4c3d-8e9f-0a1b2c3d4e5f',
  deviceSeq: 1,
  type,
  bookingId,
  occurredAt: '2026-03-05T07:00:00Z',
  payload,
});

describe('device event pre-validation (review M4)', () => {
  it('rejects junk before any database work', () => {
    expect(precheckEvent(ev('teleport'))).toBe('UNKNOWN_EVENT_TYPE');
    expect(precheckEvent(ev('postponed', { steps: 0 }))).toBe('INVALID_PAYLOAD');
    expect(precheckEvent(ev('service_started', {}, null))).toBe('BOOKING_REQUIRED');
    expect(precheckEvent({ ...ev('break_ended', {}, null), occurredAt: 'yesterday' })).toBe('INVALID_TIME');
    expect(precheckEvent(ev('break_started', { kind: 'nap' }, null))).toBe('INVALID_PAYLOAD');
  });

  it('accepts well-formed events', () => {
    expect(precheckEvent(ev('postponed', { steps: 2 }))).toBeNull();
    expect(precheckEvent(ev('break_started', { kind: 'rest' }, null))).toBeNull();
    expect(precheckEvent(ev('payment_confirmed', { amount: 5000 }))).toBeNull();
  });
});

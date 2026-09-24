import type { SettingsRow } from '../settings/settings.repository';
import type { TenantQueryable, TenantSalon } from '../tenancy/tenant-context';
import { Effects, lockDays } from './day';
import type { Shift } from './time';

/**
 * Review (lock ordering): every barber day an operation touches is locked — in one consistent order
 * — before anything emits a change (the change feed's counter row is locked by the first emitted
 * change until commit, so emitting between two day locks can deadlock two transactions).
 */
describe('lockDays', () => {
  const settings = {
    booking_opens_before_minutes: 60,
    eta_change_notify_minutes: 30,
    max_disconnect_window_minutes: 120,
    gap_margin_min_minutes: 10,
    gap_margin_percent: 25,
    offer_hold_minutes: 2,
    overrun_alert_percent: 100,
  } as SettingsRow;
  const shift = (d: string): Shift => ({ workDate: d, workStart: Date.parse(`${d}T06:00:00Z`), workEnd: Date.parse(`${d}T20:00:00Z`) });
  const now = Date.parse('2026-03-05T07:00:00Z');

  function fakeDb() {
    const log: string[] = [];
    const q = {
      async query(sql: string, params: unknown[] = []) {
        const s = sql.replace(/\s+/g, ' ').trim();
        if (/FROM barber_days .*FOR UPDATE/.test(s)) {
          log.push(`lock ${params[0]}|${params[1]}`);
          return { rows: [{ id: `day-${params[0]}`, staff_id: params[0], work_date: params[1], state: 'not_connected_yet', first_connected_at: null, last_heartbeat_at: null }], rowCount: 1 };
        }
        if (s.startsWith('SELECT id, name, role, active')) return { rows: [{ id: params[0], name: 'B', role: 'barber', active: true, call_ahead_minutes: 20, created_at: new Date(0) }], rowCount: 1 };
        if (s.includes("b.status IN ('offered', 'waiting', 'called', 'in_service')")) {
          // Every day holds one offer that has already expired → releasing it emits changes.
          return { rows: [expiredOffer(`offer-${params[0]}`, String(params[0]), String(params[1]))], rowCount: 1 };
        }
        if (s.startsWith('INSERT INTO changes')) log.push('emit');
        return { rows: [], rowCount: 0 };
      },
    } as unknown as TenantQueryable;
    return { q, log };
  }

  function expiredOffer(id: string, staffId: string, workDate: string) {
    return {
      id, customer_id: 'c', staff_id: staffId, kind: 'requested', requested_at: new Date(now), status: 'offered', queue_position: 0,
      original_expected_start: null, last_shown_expected_start: null, postpone_used: false, actual_start: null, actual_end: null, source: 'app',
      work_date: workDate, offer_expires_at: new Date(now - 1000), estimated_duration_seconds: 1800, service_set_key: 'x', projected_start: null,
      projected_end: null, last_change_reason: null, last_change_at: null, called_at: null, cancelled_at: null, cancel_reason: null,
      overrun_alerted_at: null, serve_late: false, replaces_booking_id: null, needs_review: false, reference_before_advance: null, told_expected_start: null,
      day_closed_at: null, created_at: new Date(now - 60_000), updated_at: new Date(now), customer_name: 'n', customer_phone: '0500000000',
      customer_is_walk_in: false,
    };
  }

  it('locks all days in (staff id, work date) order before any change is emitted', async () => {
    const { q, log } = fakeDb();
    const salon = { id: 's', code: 'AB-12', name: 'x', status: 'active', timezone: 'Asia/Riyadh', currency: 'SAR' } as unknown as TenantSalon;
    const days = await lockDays(
      q,
      salon,
      [
        { staffId: 'b-2', shift: shift('2026-03-05') },
        { staffId: 'a-1', shift: shift('2026-03-05') },
        { staffId: 'b-2', shift: shift('2026-03-04') },
        { staffId: 'a-1', shift: shift('2026-03-05') }, // duplicate
      ],
      now,
      settings,
      new Effects(),
    );
    expect([...days.keys()]).toEqual(['a-1|2026-03-05', 'b-2|2026-03-04', 'b-2|2026-03-05']);
    const locks = log.filter((l) => l.startsWith('lock'));
    expect(locks).toEqual(['lock a-1|2026-03-05', 'lock b-2|2026-03-04', 'lock b-2|2026-03-05']);
    const lastLock = log.lastIndexOf(locks[locks.length - 1]!);
    const firstEmit = log.indexOf('emit');
    expect(firstEmit).toBeGreaterThan(lastLock);
  });
});

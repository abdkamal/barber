import { randomUUID } from 'node:crypto';
import { staffLogin, salonQuery, startApp, TestContext } from './helpers';
import { SyncService } from '../src/sync/sync.service';
import { TenantResolver } from '../src/tenancy/tenant-resolver.service';
import { at, auth, book, clock, closeQueueApp, dropCreatedSalons, event, newCustomer, notifications, QueueSalon, settle, setupQueueSalon, T0 } from './queue-helpers';

/** ق40: a manager uploads the pending offline events of a suspended barber from his device. */
describe('recovery of a suspended account\'s offline events (ق40)', () => {
  let ctx: TestContext;
  beforeAll(async () => {
    ctx = await startApp();
  });
  afterAll(() => closeQueueApp(ctx));
  beforeEach(() => clock(ctx).set(T0));
  afterEach(() => dropCreatedSalons(ctx));

  const mgr = (s: QueueSalon) => auth(s.manager.accessToken);
  const suspend = async (s: QueueSalon, staffId: string, active = false) => {
    const r = await ctx.http().put(`/v1/manager/staff/${staffId}`).set(mgr(s)).send({ active });
    expect(r.status).toBe(200);
    return r.body;
  };
  const recover = (token: string, staffId: string, events: unknown[]) =>
    ctx.http().post(`/v1/manager/staff/${staffId}/recover-events`).set(auth(token)).send({ events });

  it('applies events before the suspension (flagged, marked, audited), reports later ones, and is idempotent', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const c = await newCustomer(ctx, s);
    const id = (await book(ctx, c, { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    // Offline on the barber's device: started, finished, then (after the suspension) payment.
    const started = event(ctx, b, 'service_started', id, {}, at(1));
    const finished = event(ctx, b, 'service_finished', id, {}, at(10) - 1); // 1 ms before the suspension
    const paid = event(ctx, b, 'payment_confirmed', id, { amount: 5000 }, at(10)); // exactly at it → refused
    clock(ctx).set(at(10));
    const staff = await suspend(s, b.id);
    expect(staff.suspended_at).toBe(new Date(at(10)).toISOString());
    // The barber cannot sync himself any more.
    expect((await ctx.http().post('/v1/sync/events').set(auth(b.token)).send({ events: [started] })).status).toBe(401);

    clock(ctx).set(at(60));
    const r = await recover(s.manager.accessToken, b.id, [started, finished, paid]);
    expect(r.status).toBe(200);
    expect(r.body).toEqual({
      staffId: b.id,
      suspendedAt: new Date(at(10)).toISOString(),
      results: [
        { eventId: started.id, result: 'applied' },
        { eventId: finished.id, result: 'applied' },
        { eventId: paid.id, result: 'rejected_after_suspension', reason: 'AFTER_SUSPENSION' },
      ],
      summary: { applied: 2, duplicate: 0, rejectedAfterSuspension: 1, rejectedUncertainTime: 0, rejectedInvalid: 0 },
    });
    const [row] = await salonQuery(ctx, s.dbName, 'SELECT status, actual_start, actual_end FROM bookings WHERE id = $1', [id]);
    expect(row).toEqual({ status: 'done', actual_start: new Date(at(1)), actual_end: new Date(at(10) - 1) });
    const [pay] = await salonQuery(ctx, s.dbName, 'SELECT status FROM payments WHERE booking_id = $1', [id]);
    expect(pay.status).toBe('awaiting_confirmation');
    // Attributed to the barber, marked with the manager who recovered them.
    const evs = await salonQuery(ctx, s.dbName, 'SELECT id, actor_id, recovered_by_staff_id FROM booking_events WHERE id = ANY($1::uuid[]) ORDER BY device_seq', [[started.id, finished.id]]);
    expect(evs).toEqual([
      { id: started.id, actor_id: b.id, recovered_by_staff_id: s.manager.id },
      { id: finished.id, actor_id: b.id, recovered_by_staff_id: s.manager.id },
    ]);
    const des = await salonQuery(ctx, s.dbName, 'SELECT id, staff_id, result, reason, flagged, recovered_by_staff_id FROM device_events ORDER BY device_seq');
    expect(des).toEqual([
      { id: started.id, staff_id: b.id, result: 'applied', reason: null, flagged: true, recovered_by_staff_id: s.manager.id },
      { id: finished.id, staff_id: b.id, result: 'applied', reason: null, flagged: true, recovered_by_staff_id: s.manager.id },
      { id: paid.id, staff_id: b.id, result: 'rejected', reason: 'AFTER_SUSPENSION', flagged: true, recovered_by_staff_id: s.manager.id },
    ]);
    const audit = await salonQuery(ctx, s.dbName, "SELECT actor_id, target_id, details FROM audit_log WHERE action = 'staff.events_recovered'");
    expect(audit).toHaveLength(1);
    expect(audit[0]).toMatchObject({
      actor_id: s.manager.id,
      target_id: b.id,
      details: { total: 3, summary: { applied: 2, duplicate: 0, rejectedAfterSuspension: 1, rejectedUncertainTime: 0, rejectedInvalid: 0 }, appliedEventIds: [started.id, finished.id] },
    });
    // Only the recovered (applied) events wait for review; no alert for the refused one.
    expect(await salonQuery(ctx, s.dbName, "SELECT kind FROM sync_conflicts ORDER BY created_at")).toEqual([{ kind: 'recovered_event' }, { kind: 'recovered_event' }]);

    // Retry of the whole upload (answer lost): nothing is applied twice; the refusal is reported again.
    const again = await recover(s.manager.accessToken, b.id, [started, finished, paid]);
    expect(again.body.results.map((x: { result: string }) => x.result)).toEqual(['duplicate', 'duplicate', 'rejected_after_suspension']);
    expect(await salonQuery(ctx, s.dbName, 'SELECT 1 FROM payments')).toHaveLength(1);
    expect(await salonQuery(ctx, s.dbName, 'SELECT 1 FROM duration_samples')).toHaveLength(1);
    expect(await salonQuery(ctx, s.dbName, "SELECT 1 FROM sync_conflicts WHERE kind = 'recovered_event'")).toHaveLength(2);
    expect(await salonQuery(ctx, s.dbName, "SELECT 1 FROM audit_log WHERE action = 'staff.events_recovered'")).toHaveLength(2);
    // Review F4: one audit entry per event, written in the event's own transaction (not repeated on retry).
    const per = await salonQuery(ctx, s.dbName, "SELECT actor_id, target_id, details FROM audit_log WHERE action = 'staff.event_recovered' ORDER BY details->>'occurredAt'");
    expect(per.map((a) => [a.actor_id, a.target_id, a.details.eventId, a.details.result, a.details.reason])).toEqual([
      [s.manager.id, b.id, started.id, 'applied', null],
      [s.manager.id, b.id, finished.id, 'applied', null],
      [s.manager.id, b.id, paid.id, 'rejected', 'AFTER_SUSPENSION'],
    ]);
  });

  it('review list: pending items, acknowledgement (audited, idempotent) and the pending-items count', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const c = await newCustomer(ctx, s);
    const id = (await book(ctx, c, { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    const started = event(ctx, b, 'service_started', id, {}, at(1));
    clock(ctx).set(at(5));
    await suspend(s, b.id);
    expect((await recover(s.manager.accessToken, b.id, [started])).body.summary.applied).toBe(1);

    const list = await ctx.http().get('/v1/manager/recovered-events').set(mgr(s));
    expect(list.status).toBe(200);
    expect(list.body).toHaveLength(1);
    const item = list.body[0];
    expect(item).toMatchObject({
      staffId: b.id,
      staffName: 'Barber',
      eventId: started.id,
      type: 'service_started',
      bookingId: id,
      occurredAt: new Date(at(1)).toISOString(),
      approximate: false,
      suspendedAt: new Date(at(5)).toISOString(),
      kind: 'recovered',
      status: 'applied',
      recoveredBy: { id: s.manager.id, name: 'Owner' },
      reviewedAt: null,
      reviewedBy: null,
    });
    expect(typeof item.customerName).toBe('string');
    const report = await ctx.http().get('/v1/manager/reports?from=2026-03-01&to=2026-03-31').set(mgr(s));
    expect(report.body.pendingItems.recoveredEvents).toBe(1);

    expect((await ctx.http().post(`/v1/manager/recovered-events/${item.id}/ack`).set(mgr(s))).body).toEqual({ ok: true });
    expect((await ctx.http().post(`/v1/manager/recovered-events/${item.id}/ack`).set(mgr(s))).body).toEqual({ ok: true });
    expect((await ctx.http().get('/v1/manager/recovered-events').set(mgr(s))).body).toEqual([]);
    const all = (await ctx.http().get('/v1/manager/recovered-events?status=all').set(mgr(s))).body;
    expect(all[0]).toMatchObject({ id: item.id, reviewedBy: { id: s.manager.id, name: 'Owner' } });
    expect(all[0].reviewedAt).not.toBeNull();
    expect(await salonQuery(ctx, s.dbName, "SELECT 1 FROM audit_log WHERE action = 'staff.recovered_event_reviewed'")).toHaveLength(1);
    expect((await ctx.http().post(`/v1/manager/recovered-events/${randomUUID()}/ack`).set(mgr(s))).status).toBe(404);
    // Other sync conflicts are not "recovered events".
    const [other] = await salonQuery(ctx, s.dbName, "INSERT INTO sync_conflicts (staff_id, kind) VALUES ($1, 'rejected_event') RETURNING id", [b.id]);
    expect((await ctx.http().post(`/v1/manager/recovered-events/${other.id}/ack`).set(mgr(s))).status).toBe(404);
  });

  it('refuses non-managers, active accounts, unknown ids and other salons\' staff', async () => {
    const s = await setupQueueSalon(ctx, { barbers: 2 });
    const [b, other] = s.barbers as [typeof s.barbers[0], typeof s.barbers[0]];
    const c = await newCustomer(ctx, s);
    const id = (await book(ctx, c, { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    const started = event(ctx, b, 'service_started', id, {}, at(1));

    // Not suspended: the barber sends his own events after logging in.
    const active = await recover(s.manager.accessToken, b.id, [started]);
    expect(active.status).toBe(409);
    expect(active.body.error.code).toBe('ACCOUNT_NOT_SUSPENDED');

    clock(ctx).set(at(5));
    await suspend(s, b.id);
    // A barber cannot use the manager path — for himself or anyone else.
    expect((await recover(other.token, b.id, [started])).status).toBe(403);
    expect((await ctx.http().get('/v1/manager/recovered-events').set(auth(other.token))).status).toBe(403);
    expect((await recover(s.manager.accessToken, randomUUID(), [started])).status).toBe(404);
    expect((await recover(s.manager.accessToken, 'not-a-uuid', [started])).status).toBe(404);
    expect((await recover(s.manager.accessToken, b.id, [{ ...started, id: 'x' }])).status).toBe(400);

    // Cross-tenant: salon B's manager cannot reach salon A's barber (tenant from the token only).
    const s2 = await setupQueueSalon(ctx);
    const cross = await recover(s2.manager.accessToken, b.id, [started]);
    expect(cross.status).toBe(404);
    expect(await salonQuery(ctx, s.dbName, 'SELECT 1 FROM device_events')).toHaveLength(0);
    expect(await salonQuery(ctx, s2.dbName, 'SELECT 1 FROM device_events')).toHaveLength(0);

    // Salon A's review item is invisible (404) to salon B.
    expect((await recover(s.manager.accessToken, b.id, [started])).body.summary.applied).toBe(1);
    const [item] = (await ctx.http().get('/v1/manager/recovered-events').set(mgr(s))).body;
    expect((await ctx.http().get('/v1/manager/recovered-events').set(auth(s2.manager.accessToken))).body).toEqual([]);
    expect((await ctx.http().post(`/v1/manager/recovered-events/${item.id}/ack`).set(auth(s2.manager.accessToken))).status).toBe(404);
  });

  it('events of another booking owner or unknown bookings are rejected_invalid; state-machine rules still apply', async () => {
    const s = await setupQueueSalon(ctx, { barbers: 2 });
    const [b, other] = s.barbers as [typeof s.barbers[0], typeof s.barbers[0]];
    const c = await newCustomer(ctx, s);
    const theirs = (await book(ctx, c, { serviceIds: [s.services.haircut], kind: 'queue', barberId: other.id })).body.id;
    const notYours = event(ctx, b, 'service_started', theirs, {}, at(1));
    const unknown = event(ctx, b, 'service_finished', randomUUID(), {}, at(2));
    const junk = event(ctx, b, 'teleport', null, {}, at(2));
    clock(ctx).set(at(5));
    await suspend(s, b.id);
    const r = await recover(s.manager.accessToken, b.id, [notYours, unknown, junk]);
    expect(r.body.results).toEqual([
      { eventId: notYours.id, result: 'rejected_invalid', reason: 'NOT_YOUR_BOOKING' },
      { eventId: unknown.id, result: 'rejected_invalid', reason: 'BOOKING_NOT_FOUND' },
      { eventId: junk.id, result: 'rejected_invalid', reason: 'UNKNOWN_EVENT_TYPE' },
    ]);
    const [row] = await salonQuery(ctx, s.dbName, 'SELECT status FROM bookings WHERE id = $1', [theirs]);
    expect(row.status).not.toBe('in_service');
  });

  it('suspension time is recorded on suspension, kept while suspended and cleared on reactivation', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    clock(ctx).set(at(5));
    expect((await suspend(s, b.id)).suspended_at).toBe(new Date(at(5)).toISOString());
    clock(ctx).set(at(8));
    const again = await ctx.http().put(`/v1/manager/staff/${b.id}`).set(mgr(s)).send({ active: false, name: 'Renamed' });
    expect(again.body.suspended_at).toBe(new Date(at(5)).toISOString());
    expect((await suspend(s, b.id, true)).suspended_at).toBeNull();
    clock(ctx).set(at(20));
    expect((await suspend(s, b.id)).suspended_at).toBe(new Date(at(20)).toISOString());
    const list = (await ctx.http().get('/v1/manager/staff').set(mgr(s))).body;
    expect(list.find((x: { id: string }) => x.id === b.id).suspended_at).toBe(new Date(at(20)).toISOString());
  });
  // ─── Review 2026-09-24 (F1–F6) ──────────────────────────────────────────────────────

  it('F1: approximate device times are never applied by recovery — kept (with the amount) for manual review', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const c = await newCustomer(ctx, s);
    const id = (await book(ctx, c, { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    const exact = event(ctx, b, 'service_started', id, {}, at(1));
    const fin = event(ctx, b, 'service_finished', id, {}, at(3));
    clock(ctx).set(at(10));
    await suspend(s, b.id);
    clock(ctx).set(at(120));
    // Really done at ~at(100) (after the suspension) but the restarted device's wall clock says at(5).
    const paid = event(ctx, b, 'payment_confirmed', id, { amount: 4500 }, at(5), { approximate: true });
    const r = await recover(s.manager.accessToken, b.id, [exact, fin, paid]);
    expect(r.status).toBe(200);
    expect(r.body.results[2]).toEqual({ eventId: paid.id, result: 'rejected_uncertain_time', reason: 'UNCERTAIN_TIME' });
    expect(r.body.summary).toEqual({ applied: 2, duplicate: 0, rejectedAfterSuspension: 0, rejectedUncertainTime: 1, rejectedInvalid: 0 });
    const [pay] = await salonQuery(ctx, s.dbName, 'SELECT status FROM payments WHERE booking_id = $1', [id]);
    expect(pay.status).toBe('awaiting_confirmation');
    const [de] = await salonQuery(ctx, s.dbName, 'SELECT result, reason, approximate, payload FROM device_events WHERE id = $1', [paid.id]);
    expect(de).toEqual({ result: 'rejected', reason: 'UNCERTAIN_TIME', approximate: true, payload: { amount: 4500 } });
    // In the review list: not applied, with what the manager needs to record it by hand.
    const list = (await ctx.http().get('/v1/manager/recovered-events').set(mgr(s))).body;
    const item = list.find((x: { eventId: string }) => x.eventId === paid.id);
    expect(item).toMatchObject({
      kind: 'recovered',
      status: 'not_applied_uncertain_time',
      type: 'payment_confirmed',
      bookingId: id,
      occurredAt: new Date(at(5)).toISOString(),
      approximate: true,
      reason: 'UNCERTAIN_TIME',
      payloadSummary: { amount: 4500 },
      recoveredBy: { id: s.manager.id, name: 'Owner' },
    });
    expect(typeof item.customerName).toBe('string');
    expect(list.filter((x: { status: string }) => x.status === 'applied')).toHaveLength(2);
    // A retry reports it the same way and adds nothing.
    const again = await recover(s.manager.accessToken, b.id, [paid]);
    expect(again.body.results).toEqual([{ eventId: paid.id, result: 'rejected_uncertain_time', reason: 'UNCERTAIN_TIME' }]);
    expect(await salonQuery(ctx, s.dbName, "SELECT 1 FROM sync_conflicts WHERE kind = 'recovered_event'")).toHaveLength(3);
  });

  it('F2: after reactivation, events done while suspended are applied but flagged for review', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const c = await newCustomer(ctx, s);
    const id = (await book(ctx, c, { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    const id2 = (await book(ctx, await newCustomer(ctx, s), { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    clock(ctx).set(at(10));
    await suspend(s, b.id);
    const during = event(ctx, b, 'service_started', id, {}, at(20)); // while suspended
    clock(ctx).set(at(30));
    await suspend(s, b.id, true);
    expect(await salonQuery(ctx, s.dbName, 'SELECT suspended_at, reactivated_at FROM staff_suspensions WHERE staff_id = $1', [b.id])).toEqual([
      { suspended_at: new Date(at(10)), reactivated_at: new Date(at(30)) },
    ]);
    const finished = event(ctx, b, 'service_finished', id, {}, at(40)); // after reactivation — normal
    // Approximate time before the suspension: cannot prove it was not during it → flagged too.
    const approx = event(ctx, b, 'postponed', id2, { steps: 1 }, at(5), { approximate: true });
    clock(ctx).set(at(41));
    const login = await staffLogin(ctx, s.code, b.username);
    const r = await ctx.http().post('/v1/sync/events').set(auth(login.body.accessToken)).send({ events: [during, finished, approx] });
    expect(r.status).toBe(200);
    expect(r.body.map((x: { result: string }) => x.result)).toEqual(['applied', 'applied', 'applied']);
    const des = await salonQuery(ctx, s.dbName, 'SELECT id, flagged FROM device_events ORDER BY device_seq');
    expect(des).toEqual([
      { id: during.id, flagged: true },
      { id: finished.id, flagged: false },
      { id: approx.id, flagged: true },
    ]);
    const list = (await ctx.http().get('/v1/manager/recovered-events').set(mgr(s))).body;
    expect(list.map((x: { eventId: string }) => x.eventId).sort()).toEqual([during.id, approx.id].sort());
    expect(list.find((x: { eventId: string }) => x.eventId === during.id)).toMatchObject({
      kind: 'during_suspension',
      status: 'applied',
      type: 'service_started',
      suspendedAt: new Date(at(10)).toISOString(),
      reactivatedAt: new Date(at(30)).toISOString(),
      recoveredBy: null,
    });
    // A later suspension opens a new interval; the backfilled/closed ones are kept.
    clock(ctx).set(at(50));
    await suspend(s, b.id);
    expect(await salonQuery(ctx, s.dbName, 'SELECT 1 FROM staff_suspensions WHERE staff_id = $1', [b.id])).toHaveLength(2);
  });

  it('F3: break and absence events of a suspended barber are recovered on his real shift (no alerts)', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const e1 = event(ctx, b, 'break_started', null, { kind: 'rest', durationMin: 15 }, at(1));
    const e2 = event(ctx, b, 'break_ended', null, {}, at(10));
    const e3 = event(ctx, b, 'absent_today', null, { reason: 'مريض' }, at(11));
    clock(ctx).set(at(20));
    await suspend(s, b.id);
    clock(ctx).set(at(30));
    const r = await recover(s.manager.accessToken, b.id, [e1, e2, e3]);
    expect(r.body.results).toEqual([
      { eventId: e1.id, result: 'applied' },
      { eventId: e2.id, result: 'applied' },
      { eventId: e3.id, result: 'applied' },
    ]);
    const brk = await salonQuery(ctx, s.dbName, 'SELECT work_date::text AS d, type, open, starts_at, ends_at FROM breaks WHERE staff_id = $1', [b.id]);
    expect(brk).toEqual([{ d: '2026-03-05', type: 'rest', open: false, starts_at: new Date(at(1)), ends_at: new Date(at(10)) }]);
    const abs = await salonQuery(ctx, s.dbName, 'SELECT work_date::text AS d, reason FROM absences WHERE staff_id = $1', [b.id]);
    expect(abs).toEqual([{ d: '2026-03-05', reason: 'مريض' }]);
    await settle(ctx);
    // Review F5: recovery alerts nobody (the manager sees the review list).
    expect(await notifications(ctx, s, "type IN ('barber_absent', 'sync_conflict')")).toHaveLength(0);
  });

  it('F5: a recovered start after a cancellation is flagged for review without a manager alert', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const c = await newCustomer(ctx, s);
    const id = (await book(ctx, c, { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    const started = event(ctx, b, 'service_started', id, {}, at(1));
    clock(ctx).set(at(2));
    expect((await ctx.http().post(`/v1/bookings/${id}/cancel`).set(auth(c.token))).status).toBe(200);
    clock(ctx).set(at(5));
    await suspend(s, b.id);
    const r = await recover(s.manager.accessToken, b.id, [started]);
    expect(r.body.results).toEqual([{ eventId: started.id, result: 'applied', reason: 'CONFLICT_ACTUAL_EVENT_WINS' }]);
    await settle(ctx);
    expect(await notifications(ctx, s, "type = 'sync_conflict'")).toHaveLength(0);
    const kinds = await salonQuery(ctx, s.dbName, 'SELECT kind FROM sync_conflicts ORDER BY kind');
    expect(kinds).toEqual([{ kind: 'recovered_event' }, { kind: 'started_after_cancelled' }]);
    const [row] = await salonQuery(ctx, s.dbName, 'SELECT status FROM bookings WHERE id = $1', [id]);
    expect(row.status).toBe('in_service');
  });

  it('F4/F6: the account state is re-checked in each event transaction; a stopped upload is still audited', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const c = await newCustomer(ctx, s);
    const id = (await book(ctx, c, { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    const started = event(ctx, b, 'service_started', id, {}, at(1));
    const junk = event(ctx, b, 'teleport', null, {}, at(2));
    clock(ctx).set(at(5));
    await suspend(s, b.id);
    // The service is called with a stale view of the account (reactivated/re-suspended meanwhile).
    const t = (await ctx.app.get(TenantResolver).fromVerifiedToken(s.id))!;
    const sync = ctx.app.get(SyncService);
    const manager = { salonId: s.id, subjectId: s.manager.id, role: 'manager' as const, sessionId: randomUUID() };
    await expect(sync.recoverBatch(t, manager, { id: b.id, role: 'barber', suspendedAt: new Date(at(4)) }, [junk, started], null)).rejects.toMatchObject({
      code: 'ACCOUNT_NOT_SUSPENDED',
    });
    // Nothing recorded for the refused event (it stays on the device); the junk one was recorded.
    expect(await salonQuery(ctx, s.dbName, 'SELECT id FROM device_events')).toEqual([{ id: junk.id }]);
    const [audit] = await salonQuery(ctx, s.dbName, "SELECT details FROM audit_log WHERE action = 'staff.events_recovered'");
    expect(audit.details).toMatchObject({ total: 2, complete: false, summary: { rejectedInvalid: 1, applied: 0 } });
    // Reactivated: a normal push after the manager path is refused mid-way stays consistent.
    await suspend(s, b.id, true);
    expect((await recover(s.manager.accessToken, b.id, [started])).status).toBe(409);
  });

  it('F6: concurrent uploads of the same event report it as a duplicate, never as refused', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const c = await newCustomer(ctx, s);
    const id = (await book(ctx, c, { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    const started = event(ctx, b, 'service_started', id, {}, at(1));
    clock(ctx).set(at(5));
    await suspend(s, b.id);
    const rs = await Promise.all([1, 2, 3].map(() => recover(s.manager.accessToken, b.id, [started])));
    const results = rs.map((r) => r.body.results[0].result).sort();
    expect(results.filter((x) => x === 'applied')).toHaveLength(1);
    expect(results.every((x) => x === 'applied' || x === 'duplicate')).toBe(true);
    const [de] = await salonQuery(ctx, s.dbName, 'SELECT result FROM device_events WHERE id = $1', [started.id]);
    expect(de.result).toBe('applied');
  });
});

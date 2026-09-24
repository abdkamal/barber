import { randomUUID } from 'node:crypto';
import { salonQuery, startApp, TestContext } from './helpers';
import { at, auth, book, clock, closeQueueApp, dropCreatedSalons, event, newCustomer, QueueSalon, setupQueueSalon, T0 } from './queue-helpers';

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
      summary: { applied: 2, duplicate: 0, rejectedAfterSuspension: 1, rejectedInvalid: 0 },
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
      details: { total: 3, summary: { applied: 2, duplicate: 0, rejectedAfterSuspension: 1, rejectedInvalid: 0 }, appliedEventIds: [started.id, finished.id] },
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
});

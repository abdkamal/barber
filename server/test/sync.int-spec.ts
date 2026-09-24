import { randomUUID } from 'node:crypto';
import type { AddressInfo } from 'node:net';
import { SyncService } from '../src/sync/sync.service';
import { TenantResolver } from '../src/tenancy/tenant-resolver.service';
import { StaffStream } from '../src/sync/staff-stream';
import { salonQuery, startApp, TestContext } from './helpers';
import {
  at,
  auth,
  book,
  clock,
  event,
  heartbeat,
  isoAt,
  newCustomer,
  notifications,
  push,
  runScheduler,
  settle,
  setupQueueSalon,
  staffToday,
  T0,
  closeQueueApp,
  dropCreatedSalons,
} from './queue-helpers';

/** Device sync (design §6) through the booking state machine (§3). */
describe('staff sync', () => {
  let ctx: TestContext;
  beforeAll(async () => {
    ctx = await startApp();
  });
  afterAll(() => closeQueueApp(ctx));
  beforeEach(() => clock(ctx).set(T0));
  afterEach(() => dropCreatedSalons(ctx));

  const walkIn = (token: string, body: Record<string, unknown>, key = randomUUID()) =>
    ctx.http().post('/v1/staff/walk-ins').set(auth(token)).set('Idempotency-Key', key).send(body);

  it('applies events in deviceSeq order, once per event id, using occurredAt as the real time', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const c = await newCustomer(ctx, s);
    const id = (await book(ctx, c, { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    await heartbeat(ctx, b);
    const start = event(ctx, b, 'service_started', id, {}, at(1));
    const finish = event(ctx, b, 'service_finished', id, {}, at(29));
    clock(ctx).set(at(40));
    // Sent out of order: the server sorts by deviceSeq; results come back in the order sent.
    const out = await push(ctx, b, [finish, start]);
    expect(out).toEqual([
      { eventId: finish.id, result: 'applied' },
      { eventId: start.id, result: 'applied' },
    ]);
    const [row] = await salonQuery(ctx, s.dbName, 'SELECT status, actual_start, actual_end FROM bookings WHERE id = $1', [id]);
    expect(row).toEqual({ status: 'done', actual_start: new Date(at(1)), actual_end: new Date(at(29)) });
    // Retry of the whole batch: all duplicates, nothing applied twice.
    const again = await push(ctx, b, [start, finish]);
    expect(again.map((r) => r.result)).toEqual(['duplicate', 'duplicate']);
    expect(await salonQuery(ctx, s.dbName, 'SELECT 1 FROM payments')).toHaveLength(1);
    expect(await salonQuery(ctx, s.dbName, 'SELECT 1 FROM duration_samples')).toHaveLength(1);
    const evs = await salonQuery(ctx, s.dbName, 'SELECT id, device_seq FROM booking_events WHERE id = ANY($1::uuid[]) ORDER BY device_seq', [[start.id, finish.id]]);
    expect(evs.map((e) => e.id)).toEqual([start.id, finish.id]);
  });

  it('approximate times are applied but excluded from duration learning (ق11)', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const c = await newCustomer(ctx, s);
    const id = (await book(ctx, c, { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    await push(ctx, b, [event(ctx, b, 'service_started', id, {}, at(0))]);
    clock(ctx).set(at(30));
    const out = await push(ctx, b, [event(ctx, b, 'service_finished', id, {}, at(28), { approximate: true })]);
    expect(out[0]!.result).toBe('applied');
    const [smp] = await salonQuery(ctx, s.dbName, 'SELECT excluded, exclusion_reason FROM duration_samples');
    expect(smp).toEqual({ excluded: true, exclusion_reason: 'approximate_time' });
  });

  it('ق22: starting a walk-in before the called customer counts as his postponement and notifies him', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const c = await newCustomer(ctx, s);
    const id = (await book(ctx, c, { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    await heartbeat(ctx, b);
    await runScheduler(ctx, s); // calls c
    const w = await walkIn(b.token, { name: 'زبون حاضر', phone: '0555000111', serviceIds: [s.services.beard] });
    expect(w.status).toBe(201);
    expect(w.body).toMatchObject({ walkIn: true, source: 'barber', status: 'waiting', queuePosition: 1, customerName: 'زبون حاضر' });
    const out = await push(ctx, b, [event(ctx, b, 'service_started', w.body.id)]);
    expect(out[0]!.result).toBe('applied');
    const [row] = await salonQuery(ctx, s.dbName, 'SELECT status, postpone_used, last_change_reason FROM bookings WHERE id = $1', [id]);
    expect(row).toEqual({ status: 'waiting', postpone_used: true, last_change_reason: 'skipped' });
    await settle(ctx);
    const n = await notifications(ctx, s, "recipient_id = $1 AND type = 'postponed'", [c.id]);
    expect(n).toHaveLength(1);
    expect(n[0].body).toContain('تم تأجيل دورك');
    // Postponement is used: a no-show is now possible.
    expect((await push(ctx, b, [event(ctx, b, 'no_show', id)]))[0]!.result).toBe('applied');
  });

  it('ق10/ق21: postpone once (N steps, next called at once); no-show only after it', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const [c1, c2, c3] = [await newCustomer(ctx, s), await newCustomer(ctx, s), await newCustomer(ctx, s)];
    const svc = [s.services.haircut];
    const r1 = (await book(ctx, c1, { serviceIds: svc, kind: 'queue' })).body.id;
    const r2 = (await book(ctx, c2, { serviceIds: svc, kind: 'queue' })).body.id;
    const r3 = (await book(ctx, c3, { serviceIds: svc, kind: 'queue' })).body.id;
    await heartbeat(ctx, b);
    await runScheduler(ctx, s);
    expect((await salonQuery(ctx, s.dbName, 'SELECT status FROM bookings WHERE id = $1', [r1]))[0].status).toBe('called');

    const early = await push(ctx, b, [event(ctx, b, 'no_show', r1)]);
    expect(early[0]).toMatchObject({ result: 'rejected', reason: 'NO_SHOW_BEFORE_POSTPONEMENT' });
    const waitedEarly = await push(ctx, b, [event(ctx, b, 'waited', r1)]);
    expect(waitedEarly[0]).toMatchObject({ result: 'rejected', reason: 'NOT_POSTPONED' });

    const p = await push(ctx, b, [event(ctx, b, 'postponed', r1, { steps: 2 })]);
    expect(p[0]!.result).toBe('applied');
    const rows = await salonQuery(ctx, s.dbName, "SELECT id, status, queue_position FROM bookings WHERE status IN ('waiting','called') ORDER BY queue_position");
    // r2 is called immediately; r1 went back two turns.
    expect(rows).toEqual([
      { id: r2, status: 'called', queue_position: 0 },
      { id: r3, status: 'waiting', queue_position: 1 },
      { id: r1, status: 'waiting', queue_position: 2 },
    ]);
    const twice = await push(ctx, b, [event(ctx, b, 'postponed', r1, { steps: 1 })]);
    expect(twice[0]).toMatchObject({ result: 'rejected', reason: 'POSTPONE_ALREADY_USED' });
    expect((await push(ctx, b, [event(ctx, b, 'waited', r1)]))[0]!.result).toBe('applied');
    expect((await push(ctx, b, [event(ctx, b, 'no_show', r1)]))[0]!.result).toBe('applied');
    const [cust] = await salonQuery(ctx, s.dbName, 'SELECT no_show_count FROM customers WHERE id = $1', [c1.id]);
    expect(cust.no_show_count).toBe(1);
    await settle(ctx);
    const types = (await notifications(ctx, s)).filter((n) => n.recipient_id !== s.manager.id).map((n) => `${n.recipient_id === c1.id ? 'c1' : n.recipient_id === c2.id ? 'c2' : 'c3'}:${n.type}`);
    expect(types).toEqual(expect.arrayContaining(['c1:called', 'c2:called', 'c1:postponed', 'c1:no_show']));
    // Rejected transitions are recorded for the manager.
    expect(await salonQuery(ctx, s.dbName, "SELECT 1 FROM sync_conflicts WHERE kind = 'rejected_event'")).toHaveLength(3);
  });

  it('ق23: lateness caused by being moved earlier by > 30 min does not use up the postponement', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const [c1, c2, c3] = [await newCustomer(ctx, s), await newCustomer(ctx, s), await newCustomer(ctx, s)];
    const r1 = (await book(ctx, c1, { serviceIds: [s.services.long], kind: 'queue' })).body.id;
    const r2 = (await book(ctx, c2, { serviceIds: [s.services.haircut], kind: 'queue' })).body.id; // shown 11:00
    await book(ctx, c3, { serviceIds: [s.services.haircut], kind: 'queue' });
    await ctx.http().post(`/v1/bookings/${r1}/cancel`).set(auth(c1.token)); // r2 now expected at 10:00
    await heartbeat(ctx, b);
    const out = await push(ctx, b, [event(ctx, b, 'postponed', r2, { steps: 1 })]);
    expect(out[0]).toMatchObject({ result: 'applied', reason: 'POSTPONEMENT_NOT_COUNTED' });
    const [row] = await salonQuery(ctx, s.dbName, 'SELECT postpone_used FROM bookings WHERE id = $1', [r2]);
    expect(row.postpone_used).toBe(false);
    // The right to a (counted) postponement is still there.
    expect((await push(ctx, b, [event(ctx, b, 'postponed', r2, { steps: 1 })]))[0]).toMatchObject({ result: 'applied' });
    expect((await salonQuery(ctx, s.dbName, 'SELECT postpone_used FROM bookings WHERE id = $1', [r2]))[0].postpone_used).toBe(true);
  });

  it('walk-ins: online only on the server side — refused for an absent barber; ق26 stops bookings', async () => {
    const s = await setupQueueSalon(ctx, { barbers: 2 });
    const [b1, b2] = s.barbers;
    const c = await newCustomer(ctx, s);
    await book(ctx, c, { serviceIds: [s.services.haircut], barberId: b1!.id, kind: 'queue' });
    const out = await push(ctx, b1!, [event(ctx, b1!, 'absent_today', null, { reason: 'مريض' })]);
    expect(out[0]!.result).toBe('applied');
    const w = await walkIn(b1!.token, { name: 'حاضر', phone: '0555000222', serviceIds: [s.services.haircut] });
    expect(w.status).toBe(409);
    expect(w.body.error.code).toBe('BARBER_ABSENT');
    const c2 = await newCustomer(ctx, s);
    const direct = await book(ctx, c2, { serviceIds: [s.services.haircut], barberId: b1!.id, kind: 'queue' });
    expect(direct.body.error.code).toBe('BARBER_ABSENT');
    const auto = await book(ctx, c2, { serviceIds: [s.services.haircut], kind: 'queue' });
    expect(auto.body.barberId).toBe(b2!.id);
    await settle(ctx);
    const alerts = await notifications(ctx, s, "type = 'barber_absent'");
    expect(alerts).toHaveLength(1);
    expect(alerts[0].recipient_id).toBe(s.manager.id);
    expect((await staffToday(ctx, b1!)).day.state).toBe('absent_today');
  });

  it('phase 11: a barber undoes his own «لن أعمل اليوم» — booking resumes, managers told, idempotent, audited', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const c = await newCustomer(ctx, s);
    await heartbeat(ctx, b);
    expect((await push(ctx, b, [event(ctx, b, 'absent_today', null, { reason: 'مريض' })]))[0]!.result).toBe('applied');
    const today = await staffToday(ctx, b);
    expect(today.day.state).toBe('absent_today');
    expect(today.day.absence).toEqual({ reason: 'مريض', recordedBy: 'self', canUndo: true });
    // ق26: an emergency break on an absent day is refused with a clear code.
    const brk = await push(ctx, b, [event(ctx, b, 'break_started', null, { kind: 'emergency' })]);
    expect(brk[0]).toMatchObject({ result: 'rejected', reason: 'BARBER_ABSENT' });
    expect((await book(ctx, c, { serviceIds: [s.services.haircut], barberId: b.id, kind: 'queue' })).body.error.code).toBe('BARBER_ABSENT');

    clock(ctx).set(at(5));
    const undo = event(ctx, b, 'absent_cancelled', null, {});
    expect(await push(ctx, b, [undo])).toEqual([{ eventId: undo.id, result: 'applied' }]);
    const after = await staffToday(ctx, b);
    expect(after.day.state).not.toBe('absent_today');
    expect(after.day.absence).toBeNull();
    expect(await salonQuery(ctx, s.dbName, 'SELECT 1 FROM absences')).toHaveLength(0);
    await heartbeat(ctx, b); // still connected (ق3)
    const rebook = await book(ctx, c, { serviceIds: [s.services.haircut], barberId: b.id, kind: 'queue' });
    expect(rebook.body).toMatchObject({ barberId: b.id });
    // Retry of the same event: duplicate; a second undo: applied as a no-op.
    expect((await push(ctx, b, [undo]))[0]!.result).toBe('duplicate');
    expect((await push(ctx, b, [event(ctx, b, 'absent_cancelled', null, {})]))[0]).toMatchObject({ result: 'applied', reason: 'NOT_ABSENT' });
    // Break allowed again once present.
    expect((await push(ctx, b, [event(ctx, b, 'break_started', null, { kind: 'emergency' })]))[0]!.result).toBe('applied');
    await settle(ctx);
    const alerts = await notifications(ctx, s, "type = 'barber_absence_cancelled'");
    expect(alerts).toHaveLength(1);
    expect(alerts[0].recipient_id).toBe(s.manager.id);
    const audit = await salonQuery(ctx, s.dbName, "SELECT actor_id, details FROM audit_log WHERE action = 'staff.absence_cancelled'");
    expect(audit).toHaveLength(1);
    expect(audit[0].actor_id).toBe(b.id);
    const ds = await salonQuery(ctx, s.dbName, "SELECT data FROM changes WHERE type = 'day_state' AND staff_id = $1 ORDER BY seq DESC LIMIT 1", [b.id]);
    expect(ds[0].data.state).not.toBe('absent_today');
  });

  it('phase 11: a barber cannot undo an absence the manager recorded; the manager can (own day by event, any barber by DELETE)', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const workDate = (await staffToday(ctx, b)).day.workDate;
    const created = await ctx
      .http()
      .post('/v1/manager/absences')
      .set(auth(s.manager.accessToken))
      .send({ staffId: b.id, workDate });
    expect(created.status).toBe(201);
    expect((await staffToday(ctx, b)).day.absence).toMatchObject({ recordedBy: 'manager', canUndo: false });
    const refused = await push(ctx, b, [event(ctx, b, 'absent_cancelled', null, {})]);
    expect(refused[0]).toMatchObject({ result: 'rejected', reason: 'ABSENCE_SET_BY_MANAGER' });
    const del = await ctx.http().delete(`/v1/manager/absences/${created.body.id}`).set(auth(s.manager.accessToken));
    expect(del.status).toBe(200);
    expect((await staffToday(ctx, b)).day.state).not.toBe('absent_today');

    // The manager (who also cuts hair) undoes his own absence from his device — no alert to himself.
    for (let d = 0; d < 7; d++) {
      await salonQuery(ctx, s.dbName, 'INSERT INTO work_schedules (staff_id, weekday, opens_at, closes_at) VALUES ($1, $2, $3, $4)', [s.manager.id, d, '09:00', '23:00']);
    }
    const m = { id: s.manager.id, username: s.manager.username, token: s.manager.accessToken, seq: 0 };
    expect((await push(ctx, m, [event(ctx, m, 'absent_today', null, {})]))[0]!.result).toBe('applied');
    expect((await staffToday(ctx, m)).day.absence).toMatchObject({ recordedBy: 'self', canUndo: true });
    expect((await push(ctx, m, [event(ctx, m, 'absent_cancelled', null, {})]))[0]!.result).toBe('applied');
    expect((await staffToday(ctx, m)).day.absence).toBeNull();
    await settle(ctx);
    expect(await notifications(ctx, s, "type = 'barber_absence_cancelled'")).toHaveLength(0);
  });

  it('design §3: an offline start after the customer cancelled — the actual event wins, flagged for the manager', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const c = await newCustomer(ctx, s);
    const id = (await book(ctx, c, { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    const started = event(ctx, b, 'service_started', id, {}, at(1));
    clock(ctx).set(at(2));
    expect((await ctx.http().post(`/v1/bookings/${id}/cancel`).set(auth(c.token))).status).toBe(200);
    clock(ctx).set(at(5));
    const out = await push(ctx, b, [started]);
    expect(out[0]).toMatchObject({ result: 'applied', reason: 'CONFLICT_ACTUAL_EVENT_WINS' });
    const [row] = await salonQuery(ctx, s.dbName, 'SELECT status, needs_review, actual_start FROM bookings WHERE id = $1', [id]);
    expect(row).toEqual({ status: 'in_service', needs_review: true, actual_start: new Date(at(1)) });
    expect(await salonQuery(ctx, s.dbName, "SELECT kind FROM sync_conflicts WHERE booking_id = $1", [id])).toEqual([{ kind: 'started_after_cancelled' }]);
    await settle(ctx);
    expect(await notifications(ctx, s, "type = 'sync_conflict'")).toHaveLength(1);
    const [de] = await salonQuery(ctx, s.dbName, 'SELECT flagged FROM device_events WHERE id = $1', [started.id]);
    expect(de.flagged).toBe(true);
  });

  it('design §6.5: events from a revoked account are accepted before the revocation (flagged) and refused after', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const c = await newCustomer(ctx, s);
    const id = (await book(ctx, c, { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    const t = (await ctx.app.get(TenantResolver).fromVerifiedToken(s.id))!;
    const me = { salonId: s.id, subjectId: b.id, role: 'barber' as const, sessionId: randomUUID() };
    const sync = ctx.app.get(SyncService);
    const before = event(ctx, b, 'service_started', id, {}, at(1));
    const after = event(ctx, b, 'service_finished', id, {}, at(20));
    clock(ctx).set(at(30));
    const out = await sync.applyBatch(t, me, [before, after], { revokedAt: at(10) });
    expect(out).toEqual([
      { eventId: before.id, result: 'applied' },
      { eventId: after.id, result: 'rejected', reason: 'ACCOUNT_REVOKED' },
    ]);
    const kinds = await salonQuery(ctx, s.dbName, 'SELECT kind FROM sync_conflicts ORDER BY created_at');
    expect(kinds.map((k) => k.kind).sort()).toEqual(['event_from_revoked_account', 'rejected_event']);
  });

  it('services_changed (ق9) re-estimates and re-prices; impact preview lists delays, ق24 and ق5 flags', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const [c1, c2] = [await newCustomer(ctx, s), await newCustomer(ctx, s)];
    const r1 = (await book(ctx, c1, { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    const r2 = (await book(ctx, c2, { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    await heartbeat(ctx, b);
    await push(ctx, b, [event(ctx, b, 'service_started', r1)]);
    const imp = await ctx.http().post('/v1/staff/impact').set(auth(b.token)).send({ bookingId: r1, serviceIds: [s.services.haircut, s.services.long] });
    expect(imp.status).toBe(200);
    expect(imp.body).toMatchObject({ newDurationMin: 90, oldDurationMin: 30, newPriceCents: 15000, oldPriceCents: 5000 });
    expect(imp.body.changes).toEqual([expect.objectContaining({ bookingId: r2, deltaMin: 60, notify: true, pastClosing: false })]);
    const out = await push(ctx, b, [event(ctx, b, 'services_changed', r1, { serviceIds: [s.services.haircut, s.services.long] })]);
    expect(out[0]!.result).toBe('applied');
    const today = await staffToday(ctx, b);
    expect(today.queue.map((q: { id: string; eta: string }) => [q.id, q.eta])).toEqual([
      [r1, isoAt(0)],
      [r2, isoAt(90)],
    ]);
    expect(today.queue[0].priceCents).toBe(15000);
    const [ev] = await salonQuery(ctx, s.dbName, "SELECT reason FROM booking_events WHERE booking_id = $1 AND type = 'eta_changed'", [r2]);
    expect(ev.reason).toBe('services_changed');
    const closing = await push(ctx, b, [event(ctx, b, 'closing_decision', r2, { decision: 'cancel', reason: 'انتهى الدوام' })]);
    expect(closing[0]!.result).toBe('applied');
    expect((await salonQuery(ctx, s.dbName, 'SELECT status FROM bookings WHERE id = $1', [r2]))[0].status).toBe('cancelled');
    await settle(ctx);
    expect((await notifications(ctx, s, "type = 'cancelled_closing'"))[0].body).toContain('انتهى الدوام');
  });

  it('breaks from the device shift the queue; payments list; GET /sync returns the SyncChange shape', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const c = await newCustomer(ctx, s);
    const r = (await book(ctx, c, { serviceIds: [s.services.haircut], kind: 'queue' })).body.id;
    const t0 = await staffToday(ctx, b);
    expect(t0.queue.map((q: { id: string }) => q.id)).toEqual([r]);
    expect(t0.settings).toMatchObject({ callAheadMinutes: 20, etaChangeNotifyMinutes: 30 });
    const since = t0.seq;
    expect((await push(ctx, b, [event(ctx, b, 'break_started', null, { kind: 'emergency', durationMin: 20 })]))[0]!.result).toBe('applied');
    expect((await staffToday(ctx, b)).queue[0].eta).toBe(isoAt(20));
    expect((await push(ctx, b, [event(ctx, b, 'break_started', null, { kind: 'rest' })]))[0]).toMatchObject({ result: 'rejected', reason: 'BREAK_ALREADY_OPEN' });
    clock(ctx).set(at(5));
    expect((await push(ctx, b, [event(ctx, b, 'break_ended', null)]))[0]!.result).toBe('applied');
    expect((await staffToday(ctx, b)).queue[0].eta).toBe(isoAt(5));

    const pull = await ctx.http().get(`/v1/sync?since=${since}`).set(auth(b.token));
    expect(pull.status).toBe(200);
    expect(pull.body.seq).toBeGreaterThan(since);
    expect(pull.body.changes.length).toBeGreaterThan(0);
    for (const ch of pull.body.changes) {
      expect(Object.keys(ch).sort()).toEqual(['bookingId', 'data', 'occurredAt', 'seq', 'type']);
      expect(typeof ch.seq).toBe('number');
    }
    expect(pull.body.changes.map((x: { type: string }) => x.type)).toEqual(expect.arrayContaining(['break_started', 'queue_updated', 'break_ended']));
    const empty = await ctx.http().get(`/v1/sync?since=${pull.body.seq}`).set(auth(b.token));
    expect(empty.body.changes).toEqual([]);
    expect(empty.body.seq).toBe(pull.body.seq);
    // Unknown and malformed events are rejected, not fatal for the batch.
    const bad = await push(ctx, b, [event(ctx, b, 'teleport', r), event(ctx, b, 'postponed', r, { steps: 0 })]);
    expect(bad.map((x) => x.reason)).toEqual(['UNKNOWN_EVENT_TYPE', 'INVALID_PAYLOAD']);
  });

  it('WS /v1/staff/stream: token required, staff only, pushes change seqs of the own queue', async () => {
    const s = await setupQueueSalon(ctx, { barbers: 2 });
    const [b1, b2] = s.barbers;
    const server = ctx.app.getHttpServer();
    await new Promise<void>((res) => server.listen(0, '127.0.0.1', () => res()));
    const port = (server.address() as AddressInfo).port;
    const url = `ws://127.0.0.1:${port}/v1/staff/stream`;
    const { WebSocket } = await import('ws');
    const failStatus = (headers: Record<string, string>, u = url) =>
      new Promise<number>((res) => {
        const ws = new WebSocket(u, { headers });
        ws.on('unexpected-response', (_req, r) => res(r.statusCode ?? 0));
        ws.on('open', () => {
          res(101);
          ws.close();
        });
        ws.on('error', () => undefined);
      });
    expect(await failStatus({ Authorization: 'Bearer nope' })).toBe(401);
    const c = await newCustomer(ctx, s);
    expect(await failStatus({ Authorization: `Bearer ${c.token}` })).toBe(403);

    const open = (token: string) =>
      new Promise<{ ws: InstanceType<typeof WebSocket>; msgs: Array<{ type: string; seq: number }> }>((res, rej) => {
        const ws = new WebSocket(url, { headers: { Authorization: `Bearer ${token}` } });
        const msgs: Array<{ type: string; seq: number }> = [];
        ws.on('message', (d) => msgs.push(JSON.parse(String(d))));
        ws.on('open', () => res({ ws, msgs }));
        ws.on('error', rej);
      });
    const s1 = await open(b1!.token);
    const s2 = await open(b2!.token);
    const waitFor = async (cond: () => boolean) => {
      for (let i = 0; i < 100 && !cond(); i++) await new Promise((r) => setTimeout(r, 20));
      return cond();
    };
    expect(await waitFor(() => s1.msgs.some((m) => m.type === 'hello'))).toBe(true);
    await book(ctx, c, { serviceIds: [s.services.haircut], barberId: b1!.id, kind: 'queue' });
    expect(await waitFor(() => s1.msgs.some((m) => m.type === 'changes'))).toBe(true);
    await new Promise((r) => setTimeout(r, 100));
    expect(s2.msgs.filter((m) => m.type === 'changes')).toHaveLength(0);
    s1.ws.close();
    s2.ws.close();
    await new Promise((r) => setTimeout(r, 50));
  });

  it('L6: WS never takes the token from the URL; sub-protocol or first-message auth; ≤ 3 sockets per account; batched revalidation', async () => {
    const s = await setupQueueSalon(ctx);
    const b = s.barbers[0]!;
    const server = ctx.app.getHttpServer();
    if (!server.listening) await new Promise<void>((res) => server.listen(0, '127.0.0.1', () => res()));
    const port = (server.address() as AddressInfo).port;
    const url = `ws://127.0.0.1:${port}/v1/staff/stream`;
    const { WebSocket } = await import('ws');
    type Sock = { ws: InstanceType<typeof WebSocket>; msgs: Array<{ type: string }>; closed: Promise<number>; protocol: string };
    const connect = (u: string, protocols?: string[]) =>
      new Promise<Sock>((res, rej) => {
        const ws = new WebSocket(u, protocols);
        const msgs: Array<{ type: string }> = [];
        const closed = new Promise<number>((r) => ws.on('close', (code) => r(code)));
        ws.on('message', (d) => msgs.push(JSON.parse(String(d))));
        ws.on('open', () => res({ ws, msgs, closed, protocol: ws.protocol }));
        ws.on('error', rej);
      });
    const waitFor = async (cond: () => boolean) => {
      for (let i = 0; i < 100 && !cond(); i++) await new Promise((r) => setTimeout(r, 20));
      return cond();
    };

    // A token in the query string is ignored: no hello; a wrong first message closes with 4401.
    const q = await connect(`${url}?access_token=${b.token}`);
    await new Promise((r) => setTimeout(r, 150));
    expect(q.msgs).toHaveLength(0);
    q.ws.send('hello?');
    expect(await q.closed).toBe(4401);

    // Sub-protocol: the server selects saloni.v1 and never echoes the bearer entry.
    const p = await connect(url, ['saloni.v1', `bearer.${b.token}`]);
    expect(p.protocol).toBe('saloni.v1');
    expect(await waitFor(() => p.msgs.some((m) => m.type === 'hello'))).toBe(true);

    // First-message auth.
    const f = await connect(url);
    f.ws.send(JSON.stringify({ type: 'auth', token: b.token }));
    expect(await waitFor(() => f.msgs.some((m) => m.type === 'hello'))).toBe(true);

    // Per-account cap (3): a 4th socket closes the oldest one (4408).
    const g = await connect(url, ['saloni.v1', `bearer.${b.token}`]);
    const h = await connect(url, ['saloni.v1', `bearer.${b.token}`]);
    expect(await p.closed).toBe(4408);
    const stream = ctx.app.get(StaffStream);

    // Revalidation (one query per salon): a revoked session closes its sockets.
    await salonQuery(ctx, s.dbName, "UPDATE sessions SET revoked_at = now() WHERE subject_kind = 'staff' AND subject_id = $1", [b.id]);
    await stream.housekeeping();
    expect(await f.closed).toBe(4401);
    expect(await g.closed).toBe(4401);
    expect(await h.closed).toBe(4401);
  });
});

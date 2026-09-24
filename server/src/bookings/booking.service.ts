import { Injectable } from '@nestjs/common';
import {
  type BarberCandidate,
  changeTime,
  chooseBarber,
  confirmOffer,
  findPlacement,
  MINUTE,
  type Placement,
  placeWithBarber,
  remove,
  requestedHourOutcome,
} from '@saloni/engine';
import type { Principal } from '../auth/principal';
import { writeAudit } from '../security/audit';
import { SettingsRepo, type SettingsRow } from '../settings/settings.repository';
import type { TenantContext, TenantQueryable } from '../tenancy/tenant-context';
import { NotificationService } from '../notifications/notification.service';
import { Texts } from '../notifications/texts';
import { emitBooking, loadBooking, placeBooking, resolveServices, sumMinutes, sumPrice } from '../scheduling/booking-writer';
import { Clock } from '../scheduling/clock';
import {
  ACTIVE_BOOKING_MAX_AGE_MS,
  commitQueue,
  type DayCtx,
  type Effects,
  estimateFor,
  insertBookingEvent,
  isStaleDay,
  dayWindow,
  loadDay,
  lockDays,
  project,
  releaseExpiredOffers,
  schedulesOf,
  shiftForDate,
  stateWire,
  updateReference,
  workingStaff,
} from '../scheduling/day';
import { bookingDtos, type BookingDto } from '../scheduling/dto';
import { QErrors } from '../scheduling/errors';
import { once, type Outcome, unwrap } from '../scheduling/idempotency';
import { PostCommit } from '../scheduling/post-commit';
import { reasonText } from '../scheduling/reasons';
import { activeServices, BOOKING_SELECT, type BookingRow, type ServiceRow, type StaffInfo } from '../scheduling/rows';
import { currentShift, formatArabicTime, type Shift } from '../scheduling/time';

export interface PlaceBody {
  serviceIds: string[];
  barberId?: string;
  kind: 'queue' | 'requested';
  requestedAt?: string;
}

export interface QuoteDto {
  barberId: string;
  barberName: string;
  start: string;
  end: string;
  durationMin: number;
  price: number;
  outcome: 'accept' | 'offer';
  offerId?: string;
  offerExpiresAt?: string;
}

interface Chosen {
  ctx: DayCtx;
  placement: Placement;
  durationMs: number;
  setKey: string;
  services: ServiceRow[];
  requestedAt?: number;
}

const iso = (t: number) => new Date(t).toISOString();

/** How far a reported "seen" time may be from the server's projection and still be recorded (H1). */
export const SEEN_TOLERANCE_MS = 5 * MINUTE;

/** Customer booking flows (api.md "الزبون"; design §3, §5.2–§5.12). */
@Injectable()
export class BookingService {
  constructor(
    private readonly clock: Clock,
    private readonly post: PostCommit,
    private readonly notifications: NotificationService,
  ) {}

  // ─── Guards ─────────────────────────────────────────────────────────────────────────

  private assertActive(me: Principal): void {
    if (me.customerStatus !== 'active') throw QErrors.accountPending();
  }

  /** Serialises all booking writes of one customer (max-active check, one live offer). */
  private async lockCustomer(q: TenantQueryable, customerId: string): Promise<void> {
    await q.query("SELECT pg_advisory_xact_lock(hashtext('customer:' || $1))", [customerId]);
  }

  private async activeCount(q: TenantQueryable, customerId: string, now: number, excluding: string | null = null): Promise<number> {
    const { rows } = await q.query<{ n: string }>(
      `SELECT count(*) AS n FROM bookings
        WHERE customer_id = $1 AND status IN ('waiting', 'called', 'in_service') AND day_closed_at IS NULL
          AND created_at > $2 AND ($3::uuid IS NULL OR id <> $3)`,
      [customerId, new Date(now - ACTIVE_BOOKING_MAX_AGE_MS), excluding],
    );
    return Number(rows[0]!.n);
  }

  private async assertBelowMax(q: TenantQueryable, customerId: string, settings: SettingsRow, now: number, excluding: string | null = null) {
    if ((await this.activeCount(q, customerId, now, excluding)) >= settings.max_active_bookings_per_customer) {
      throw QErrors.maxActive(settings.max_active_bookings_per_customer);
    }
  }

  private parseRequested(body: { kind: string; requestedAt?: string }): number | undefined {
    if (body.kind !== 'requested') return undefined;
    const t = body.requestedAt ? Date.parse(body.requestedAt) : NaN;
    if (!Number.isFinite(t)) throw QErrors.outsideHours();
    return Math.floor(t / MINUTE) * MINUTE;
  }

  /** Locks the day a booking belongs to (queue mutations serialise on the barber-day row, §5.13). */
  private async lockDayOf(q: TenantQueryable, t: TenantContext, row: BookingRow, now: number, effects: Effects): Promise<DayCtx> {
    const shift = await shiftForDate(q, t.salon.timezone, row.staff_id, row.work_date);
    const ctx = await loadDay(q, t.salon, row.staff_id, shift, now, { lock: true });
    await releaseExpiredOffers(q, ctx, effects);
    return ctx;
  }

  private async ownOffers(q: TenantQueryable, customerId: string): Promise<BookingRow[]> {
    const { rows } = await q.query<BookingRow>(`${BOOKING_SELECT} WHERE b.customer_id = $1 AND b.status = 'offered'`, [customerId]);
    return rows;
  }

  /** Expires the customer's other outstanding offers (one live offer per customer) — their days are already locked. */
  private async dropOwnOffers(q: TenantQueryable, days: Map<string, DayCtx>, offers: BookingRow[], customerId: string, effects: Effects): Promise<void> {
    for (const r of offers) {
      const ctx = days.get(`${r.staff_id}|${r.work_date}`);
      if (!ctx || !ctx.byId.has(r.id)) continue;
      await this.removeFromQueue(q, ctx, r.id, 'expired', 'offer_replaced', effects, { reason: 'offer_released', actorKind: 'customer', actorId: customerId });
      ctx.rows = ctx.rows.filter((x) => x.id !== r.id);
      ctx.byId.delete(r.id);
    }
  }

  private async removeFromQueue(
    q: TenantQueryable,
    ctx: DayCtx,
    id: string,
    status: 'expired' | 'cancelled' | 'no_show',
    cancelReason: string | null,
    effects: Effects,
    o: { reason: 'offer_released' | 'cancelled_ahead'; actorKind: 'customer' | 'staff' | 'system'; actorId: string | null },
  ): Promise<void> {
    await q.query(
      `UPDATE bookings SET status = $2, queue_position = NULL, cancel_reason = $3,
              cancelled_at = CASE WHEN $2 = 'cancelled' THEN $4 ELSE cancelled_at END, updated_at = now() WHERE id = $1`,
      [id, status, cancelReason, new Date(ctx.now)],
    );
    await commitQueue(q, ctx, remove(ctx.queue, id), { reason: o.reason, primary: [id], effects, actorKind: o.actorKind, actorId: o.actorId });
    await emitBooking(q, ctx, id, 'booking_removed', effects);
  }

  // ─── Placement ─────────────────────────────────────────────────────────────────────

  /**
   * Locks the candidate barber days (sorted by id — no deadlocks between bookings) and finds
   * the placement: at the chosen barber, or the fastest one (§5.4). Enforces the booking window
   * (same day, opens before opening — §5.11), the day-state gate (§4, ق3/ق26) and ق4/ق19.
   */
  private async choose(
    q: TenantQueryable,
    t: TenantContext,
    me: Principal,
    body: PlaceBody,
    settings: SettingsRow,
    now: number,
    effects: Effects,
    opts: { dropOffers?: boolean } = {},
  ): Promise<Chosen> {
    const services = await resolveServices(q, body.serviceIds);
    const requestedAt = this.parseRequested(body);
    const all = await workingStaff(q);
    const staffs = body.barberId ? all.filter((s) => s.id === body.barberId) : all;
    if (body.barberId && !staffs.length) {
      const exists = await q.query('SELECT 1 FROM staff WHERE id = $1 AND active', [body.barberId]);
      throw exists.rowCount ? QErrors.bookingClosed() : QErrors.barberNotFound();
    }
    const lookahead = settings.booking_opens_before_minutes * MINUTE;
    let open = staffs
      .map((s) => ({ s, shift: currentShift(s.schedules, t.salon.timezone, now, lookahead) }))
      .filter((x): x is { s: (typeof staffs)[number]; shift: NonNullable<typeof x.shift> } => x.shift !== null);
    if (!open.length) throw QErrors.bookingClosed();
    if (requestedAt !== undefined) {
      open = open.filter((x) => requestedAt >= Math.max(x.shift.workStart, now - MINUTE) && requestedAt < x.shift.workEnd);
      if (!open.length) throw QErrors.outsideHours();
    }
    open.sort((a, b) => (a.s.id < b.s.id ? -1 : 1));
    const seniority = new Map(all.map((s, i) => [s.id, i]));
    // Lock ordering (review): every day this operation touches — the candidates and the days of the
    // customer's own offers it will drop — is locked (id order) before anything emits a change.
    const offers = opts.dropOffers ? await this.ownOffers(q, me.subjectId) : [];
    const specs: Array<{ staffId: string; shift: Shift; staff?: StaffInfo }> = open.map(({ s, shift }) => ({ staffId: s.id, shift, staff: s }));
    for (const o of offers) specs.push({ staffId: o.staff_id, shift: await shiftForDate(q, t.salon.timezone, o.staff_id, o.work_date) });
    const days = await lockDays(q, t.salon, specs, now, settings, effects);
    await this.dropOwnOffers(q, days, offers, me.subjectId, effects);
    const ctxs: DayCtx[] = open.map(({ s, shift }) => days.get(`${s.id}|${shift.workDate}`)!);
    const durations = new Map<string, { durationMs: number; setKey: string }>();
    for (const { s } of open) durations.set(s.id, await estimateFor(q, s.id, me.subjectId, body.serviceIds, sumMinutes(services)));
    const req = { kind: body.kind, requestedAt };
    let placement: (Placement & { barberId: string }) | null = null;
    if (body.barberId) {
      const ctx = ctxs[0]!;
      if (!ctx.gate.accepts) throw ctx.state.kind === 'absent' ? QErrors.barberAbsent() : QErrors.barberUnavailable();
      const p = placeWithBarber({ day: ctx.day, queue: ctx.queue, state: ctx.state, duration: durations.get(ctx.staff.id)!.durationMs }, now, req, ctx.policy);
      placement = p ? { ...p, barberId: ctx.staff.id } : null;
    } else {
      const candidates: BarberCandidate[] = [];
      for (const ctx of ctxs) {
        const { rows } = await q.query<{ n: string }>(
          "SELECT count(*) AS n FROM bookings WHERE staff_id = $1 AND work_date = $2 AND status NOT IN ('offered', 'expired')",
          [ctx.staff.id, ctx.shift.workDate],
        );
        candidates.push({
          day: ctx.day,
          queue: ctx.queue,
          state: ctx.state,
          duration: durations.get(ctx.staff.id)!.durationMs,
          bookingsToday: Number(rows[0]!.n),
          seniority: seniority.get(ctx.staff.id) ?? 0,
        });
      }
      placement = chooseBarber(candidates, now, req, ctxs[0]!.policy);
    }
    if (!placement) throw QErrors.noSlot();
    const ctx = ctxs.find((c) => c.staff.id === placement!.barberId)!;
    const d = durations.get(ctx.staff.id)!;
    return { ctx, placement, durationMs: d.durationMs, setKey: d.setKey, services, requestedAt };
  }

  private quoteDto(c: Chosen, outcome: 'accept' | 'offer', offer?: { id: string; expiresAt: number }): QuoteDto {
    return {
      barberId: c.ctx.staff.id,
      barberName: c.ctx.staff.name,
      start: iso(c.placement.start),
      end: iso(c.placement.end),
      durationMin: Math.round(c.durationMs / MINUTE),
      price: sumPrice(c.services),
      outcome,
      ...(offer ? { offerId: offer.id, offerExpiresAt: iso(offer.expiresAt) } : {}),
    };
  }

  /** Holds the offered time (ق13) as a tentative booking in the queue until it expires. */
  private async holdOffer(q: TenantQueryable, c: Chosen, me: Principal, effects: Effects, replaces: string | null = null): Promise<{ id: string; expiresAt: number }> {
    const expiresAt = c.ctx.now + c.ctx.policy.offerHold;
    const { id } = await placeBooking(
      q,
      c.ctx,
      {
        customerId: me.subjectId,
        source: 'app',
        kind: 'requested',
        requestedAt: c.placement.start,
        offer: true,
        offerExpiresAt: expiresAt,
        durationMs: c.durationMs,
        setKey: c.setKey,
        services: c.services,
        position: c.placement.position,
        replaces,
        actorKind: 'customer',
        actorId: me.subjectId,
      },
      effects,
    );
    return { id, expiresAt };
  }

  // ─── Endpoints ─────────────────────────────────────────────────────────────────────

  async today(t: TenantContext, me: Principal) {
    const now = this.clock.now();
    const settings = await SettingsRepo.get(t.db);
    const services = await activeServices(t.db);
    const shortest = services.length ? Math.min(...services.map((s) => s.base_duration_minutes)) : 30;
    const barbers = [];
    for (const s of await workingStaff(t.db)) {
      const shift = currentShift(s.schedules, t.salon.timezone, now, settings.booking_opens_before_minutes * MINUTE);
      if (!shift) {
        barbers.push({ id: s.id, name: s.name, photoUrl: null, dayState: 'not_connected_yet', nextAvailableStart: null, queueLength: 0, accepting: false, workStart: null, workEnd: null });
        continue;
      }
      const ctx = await loadDay(t.db, t.salon, s.id, shift, now, { settings, staff: s });
      const p = ctx.gate.accepts
        ? placeWithBarber({ day: ctx.day, queue: ctx.queue, state: ctx.state, duration: shortest * MINUTE }, now, { kind: 'queue' }, ctx.policy)
        : null;
      barbers.push({
        id: s.id,
        name: s.name,
        photoUrl: null,
        dayState: stateWire(ctx.state),
        nextAvailableStart: p ? iso(p.start) : null,
        queueLength: ctx.queue.filter((e) => !e.offer).length,
        accepting: ctx.gate.accepts,
        workStart: iso(shift.workStart),
        workEnd: iso(shift.workEnd),
      });
    }
    return {
      serverTime: iso(now),
      accountStatus: me.customerStatus ?? 'active',
      currency: t.salon.currency,
      services: services.map((s) => ({ id: s.id, name: s.name, baseDurationMin: s.base_duration_minutes, priceCents: Number(s.price_minor), active: s.active })),
      barbers,
    };
  }

  async quote(t: TenantContext, me: Principal, body: PlaceBody, key: string | null): Promise<QuoteDto> {
    this.assertActive(me);
    const out = await this.post.tx(t, (q, effects) =>
      once<QuoteDto>(q, { kind: 'customer', id: me.subjectId }, key, 'quote', async () => {
        const now = this.clock.now();
        await this.lockCustomer(q, me.subjectId);
        const settings = await SettingsRepo.get(q);
        await this.assertBelowMax(q, me.subjectId, settings, now);
        // A new hour request supersedes any offer the customer still holds (one live offer each).
        const c = await this.choose(q, t, me, body, settings, now, effects, { dropOffers: body.kind === 'requested' });
        if (c.requestedAt === undefined || requestedHourOutcome(c.placement.start, c.requestedAt) === 'accept') {
          return { status: 200, body: this.quoteDto(c, 'accept') };
        }
        const offer = await this.holdOffer(q, c, me, effects);
        return { status: 200, body: this.quoteDto(c, 'offer', offer) };
      }),
    );
    return unwrap(out);
  }

  async create(t: TenantContext, me: Principal, body: PlaceBody | { offerId: string }, key: string | null): Promise<BookingDto> {
    this.assertActive(me);
    const out = await this.post.tx(t, (q, effects) =>
      once<BookingDto>(q, { kind: 'customer', id: me.subjectId }, key, 'create_booking', async () => {
        const now = this.clock.now();
        await this.lockCustomer(q, me.subjectId);
        const settings = await SettingsRepo.get(q);
        if ('offerId' in body) return { status: 201, body: await this.acceptOffer(q, t, me, body.offerId, settings, now, effects) };
        await this.assertBelowMax(q, me.subjectId, settings, now);
        const c = await this.choose(q, t, me, body, settings, now, effects);
        if (c.requestedAt !== undefined && requestedHourOutcome(c.placement.start, c.requestedAt) === 'offer') {
          throw QErrors.slotUnavailable(`الساعة المطلوبة غير متاحة؛ أقرب وقت متاح ${formatArabicTime(c.placement.start, t.salon.timezone)}`, {
            nearest: iso(c.placement.start),
            barberId: c.ctx.staff.id,
          });
        }
        const { id, slot } = await placeBooking(
          q,
          c.ctx,
          {
            customerId: me.subjectId,
            source: 'app',
            kind: body.kind,
            requestedAt: c.requestedAt,
            offer: false,
            durationMs: c.durationMs,
            setKey: c.setKey,
            services: c.services,
            position: c.placement.position,
            idempotencyKey: key,
            actorKind: 'customer',
            actorId: me.subjectId,
          },
          effects,
        );
        await this.notifications.toCustomer(q, effects, me.subjectId, {
          type: 'booking_confirmed',
          bookingId: id,
          text: Texts.bookingConfirmed(c.ctx.staff.name, slot.start, t.salon.timezone),
        });
        return { status: 201, body: await this.dto(q, id, slot) };
      }),
    );
    return unwrap(out);
  }

  private async dto(q: TenantQueryable, id: string, slot?: { bookingId: string; start: number; end: number }): Promise<BookingDto> {
    const row = (await loadBooking(q, id))!;
    return (await bookingDtos(q, [row], slot ? new Map([[id, slot]]) : undefined))[0]!;
  }

  private async acceptOffer(q: TenantQueryable, t: TenantContext, me: Principal, offerId: string, settings: SettingsRow, now: number, effects: Effects): Promise<BookingDto> {
    const row = await loadBooking(q, offerId);
    if (!row || row.customer_id !== me.subjectId) throw QErrors.offerNotFound();
    if (row.status === 'expired') throw QErrors.offerExpired();
    if (row.status !== 'offered') throw QErrors.offerNotFound();
    const ctx = await this.lockDayOf(q, t, row, now, effects);
    const entry = ctx.queue.find((e) => e.bookingId === offerId);
    if (!entry) throw QErrors.offerExpired();

    if (row.replaces_booking_id) {
      // §5.12: the held time replaces the existing booking's time; the booking keeps its identity.
      const oldId = row.replaces_booking_id;
      const old = ctx.queue.find((e) => e.bookingId === oldId);
      if (!old || old.status !== 'waiting') throw QErrors.bookingNotActive();
      const moved = { ...old, kind: 'requested' as const, requestedAt: entry.requestedAt, offer: false };
      const next = ctx.queue.filter((e) => e.bookingId !== oldId).map((e) => (e.bookingId === offerId ? moved : e));
      await q.query(`UPDATE bookings SET status = 'expired', queue_position = NULL, cancel_reason = 'merged_into_booking', updated_at = now() WHERE id = $1`, [offerId]);
      const slots = await commitQueue(q, ctx, next, { reason: 'queue_moved', primary: [oldId], effects, actorKind: 'customer', actorId: me.subjectId });
      const slot = slots.find((s) => s.bookingId === oldId)!;
      await this.recordTimeChange(q, ctx, oldId, ctx.byId.get(oldId)!, slot.start, me.subjectId);
      await emitBooking(q, ctx, offerId, 'booking_removed', effects);
      await emitBooking(q, ctx, oldId, 'booking_updated', effects, slot);
      return this.dto(q, oldId, slot);
    }

    await this.assertBelowMax(q, me.subjectId, settings, now);
    const slots = await commitQueue(q, ctx, confirmOffer(ctx.queue, offerId), { reason: 'booked', primary: [offerId], effects, actorKind: 'customer', actorId: me.subjectId });
    const slot = slots.find((s) => s.bookingId === offerId)!;
    await q.query('UPDATE bookings SET original_expected_start = $2, last_shown_expected_start = $2, told_expected_start = $2, offer_expires_at = NULL WHERE id = $1', [offerId, new Date(slot.start)]);
    await insertBookingEvent(q, { bookingId: offerId, type: 'created', payload: { start: iso(slot.start), fromOffer: true }, occurredAt: now, actorKind: 'customer', actorId: me.subjectId, reason: 'booked' });
    await emitBooking(q, ctx, offerId, 'booking_created', effects, slot);
    await this.notifications.toCustomer(q, effects, me.subjectId, {
      type: 'booking_confirmed',
      bookingId: offerId,
      text: Texts.bookingConfirmed(ctx.staff.name, slot.start, t.salon.timezone),
    });
    return this.dto(q, offerId, slot);
  }

  private async recordTimeChange(q: TenantQueryable, ctx: DayCtx, id: string, before: BookingRow, start: number, customerId: string) {
    await q.query(`UPDATE bookings SET last_change_reason = 'customer_change', last_change_at = $2 WHERE id = $1`, [id, new Date(ctx.now)]);
    await updateReference(q, id, start, { reset: true });
    await insertBookingEvent(q, {
      bookingId: id,
      type: 'time_changed',
      payload: { before: before.projected_start?.toISOString() ?? null, after: iso(start), kind: before.kind },
      occurredAt: ctx.now,
      actorKind: 'customer',
      actorId: customerId,
      reason: 'customer_change',
    });
  }

  async rejectOffer(t: TenantContext, me: Principal, offerId: string): Promise<void> {
    await this.post.tx(t, async (q, effects) => {
      const now = this.clock.now();
      const row = await loadBooking(q, offerId);
      if (!row || row.customer_id !== me.subjectId || !['offered', 'expired'].includes(row.status)) throw QErrors.offerNotFound();
      if (row.status === 'expired') return;
      const ctx = await this.lockDayOf(q, t, row, now, effects);
      if (!ctx.byId.has(offerId)) return;
      await this.removeFromQueue(q, ctx, offerId, 'expired', 'offer_rejected', effects, { reason: 'offer_released', actorKind: 'customer', actorId: me.subjectId });
    });
  }

  async current(t: TenantContext, me: Principal) {
    const now = this.clock.now();
    const { rows } = await t.db.query<BookingRow>(
      `${BOOKING_SELECT}
        WHERE b.customer_id = $1 AND b.status IN ('waiting', 'called', 'in_service') AND b.created_at > $2 AND b.day_closed_at IS NULL
        ORDER BY b.projected_start NULLS LAST, b.created_at LIMIT 5`,
      [me.subjectId, new Date(now - ACTIVE_BOOKING_MAX_AGE_MS)],
    );
    // C1: a booking of a business day that is over is never "current", even before the scheduler closes it out.
    const win = dayWindow(await SettingsRepo.get(t.db));
    let row: BookingRow | undefined;
    for (const r of rows) {
      if (!isStaleDay(await schedulesOf(t.db, r.staff_id), t.salon.timezone, r.work_date, now, win)) {
        row = r;
        break;
      }
    }
    // No active booking is a normal state, not an error (api.md): 200 with `booking: null`.
    if (!row) return { booking: null, serverTime: iso(now) };
    const shift = await shiftForDate(t.db, t.salon.timezone, row.staff_id, row.work_date);
    const ctx = await loadDay(t.db, t.salon, row.staff_id, shift, now);
    const slots = project(ctx);
    const slot = slots.find((s) => s.bookingId === row.id) ?? null;
    const idx = ctx.queue.filter((e) => !e.offer).findIndex((e) => e.bookingId === row.id);
    const { rows: done } = await t.db.query<{ n: string }>(
      "SELECT count(*) AS n FROM bookings WHERE staff_id = $1 AND work_date = $2 AND status = 'done'",
      [row.staff_id, row.work_date],
    );
    const [booking] = await bookingDtos(t.db, [row], slot ? new Map([[row.id, slot]]) : undefined);
    const live = ctx.state.kind === 'online';
    const lastUpdate = ctx.state.kind === 'offline' ? ctx.state.offlineSince : now;
    const eta = row.status === 'in_service' && row.actual_start ? row.actual_start.getTime() : slot?.start ?? row.projected_start?.getTime() ?? now;
    return {
      booking,
      eta: iso(eta),
      etaEnd: slot ? iso(slot.end) : null,
      originalEta: booking!.originalEta,
      lastChangeReason: reasonText(row.last_change_reason),
      lastChangeReasonCode: row.last_change_reason,
      status: row.status,
      // ق39: the dot bar shows at most the last four finished turns; no numbers are displayed.
      progress: { done: Math.min(4, Number(done[0]!.n)), ahead: Math.max(0, idx) },
      live,
      dayState: stateWire(ctx.state),
      lastUpdateAt: iso(lastUpdate),
      barber: { id: ctx.staff.id, name: ctx.staff.name },
      serverTime: iso(now),
    };
  }

  /**
   * The app reports the time it actually displayed — the ق5 reference (§5.9). Review H1: the value
   * comes from the client, so it is recorded only when it is within SEEN_TOLERANCE_MS of the
   * server's own current projection (what the server showed, give or take a refresh); anything
   * else is ignored. It never feeds the ق23 exemption (see `exemptionReference`).
   */
  async seen(t: TenantContext, me: Principal, id: string, eta: number): Promise<{ recorded: boolean }> {
    const now = this.clock.now();
    const row = await loadBooking(t.db, id);
    if (!row || row.customer_id !== me.subjectId) throw QErrors.bookingNotFound();
    if (!['waiting', 'called', 'in_service'].includes(row.status) || row.day_closed_at) throw QErrors.bookingNotActive();
    if (row.status === 'in_service') return { recorded: false };
    const shift = await shiftForDate(t.db, t.salon.timezone, row.staff_id, row.work_date);
    const ctx = await loadDay(t.db, t.salon, row.staff_id, shift, now);
    const slot = project(ctx).find((s) => s.bookingId === id);
    if (!slot || Math.abs(eta - slot.start) > SEEN_TOLERANCE_MS) return { recorded: false };
    await t.db.query(
      `UPDATE bookings SET last_shown_expected_start = $3 WHERE id = $1 AND customer_id = $2 AND status IN ('waiting', 'called')`,
      [id, me.subjectId, new Date(eta)],
    );
    return { recorded: true };
  }

  /** §5.12: one atomic re-insertion under ق4; otherwise the booking stays and the nearest time is offered (held). */
  async changeTime(t: TenantContext, me: Principal, id: string, body: { kind: 'queue' | 'requested'; requestedAt?: string }, key: string | null): Promise<BookingDto> {
    this.assertActive(me);
    const out = await this.post.tx(t, (q, effects) =>
      once<BookingDto | { error: unknown }>(q, { kind: 'customer', id: me.subjectId }, key, `change_time:${id}`, async (): Promise<Outcome<BookingDto | { error: unknown }>> => {
        const now = this.clock.now();
        await this.lockCustomer(q, me.subjectId);
        const row = await loadBooking(q, id);
        if (!row || row.customer_id !== me.subjectId) throw QErrors.bookingNotFound();
        if (row.status === 'called') throw QErrors.alreadyCalled();
        if (row.status === 'in_service') throw QErrors.bookingStarted();
        if (row.status !== 'waiting') throw QErrors.bookingNotActive();
        const ctx = await this.lockDayOf(q, t, row, now, effects);
        if (!ctx.gate.accepts) throw ctx.state.kind === 'absent' ? QErrors.barberAbsent() : QErrors.barberUnavailable();
        const requestedAt = this.parseRequested(body);
        if (requestedAt !== undefined && (requestedAt < Math.max(ctx.shift.workStart, now - MINUTE) || requestedAt >= ctx.shift.workEnd)) {
          throw QErrors.outsideHours();
        }
        const opts = { appendOnly: ctx.gate.appendOnly, frozenAt: ctx.gate.frozenAt, policy: ctx.policy };
        const req = { kind: body.kind, requestedAt };
        const r = changeTime(ctx.day, ctx.queue, now, id, req, opts);
        if (r && (requestedAt === undefined || requestedHourOutcome(r.start, requestedAt) === 'accept')) {
          const slots = await commitQueue(q, ctx, r.queue, { reason: 'queue_moved', primary: [id], effects, actorKind: 'customer', actorId: me.subjectId });
          const slot = slots.find((s) => s.bookingId === id)!;
          await this.recordTimeChange(q, ctx, id, row, slot.start, me.subjectId);
          await emitBooking(q, ctx, id, 'booking_updated', effects, slot);
          return { status: 200, body: await this.dto(q, id, slot) };
        }
        if (requestedAt === undefined) throw QErrors.noSlot();
        // Nearest time at this barber, held while the current booking stays untouched.
        const entry = ctx.queue.find((e) => e.bookingId === id)!;
        const p = findPlacement(ctx.day, ctx.queue, now, { kind: 'requested', requestedAt, duration: entry.estimatedDuration, walkIn: false }, opts);
        if (!p) throw QErrors.noSlot();
        const services = await resolveServicesOf(q, id);
        const chosen: Chosen = { ctx, placement: p, durationMs: entry.estimatedDuration, setKey: row.service_set_key ?? '', services, requestedAt };
        const offer = await this.holdOffer(q, chosen, me, effects, id);
        const quote = this.quoteDto(chosen, 'offer', offer);
        const err = QErrors.slotUnavailable(
          `الساعة المطلوبة غير متاحة؛ أقرب وقت متاح ${formatArabicTime(p.start, t.salon.timezone)} ومحجوز لك مؤقتًا — حجزك الحالي باقٍ كما هو`,
          { offer: quote },
        );
        return { status: 409, body: err.getResponse() as { error: unknown } };
      }),
    );
    return unwrap(out) as BookingDto;
  }

  async cancel(t: TenantContext, me: Principal, id: string, key: string | null, ip: string): Promise<BookingDto> {
    const out = await this.post.tx(t, (q, effects) =>
      once<BookingDto>(q, { kind: 'customer', id: me.subjectId }, key, `cancel:${id}`, async () => {
        const now = this.clock.now();
        await this.lockCustomer(q, me.subjectId);
        const row = await loadBooking(q, id);
        if (!row || row.customer_id !== me.subjectId) throw QErrors.bookingNotFound();
        if (row.status === 'in_service') throw QErrors.bookingStarted();
        if (!['waiting', 'called', 'offered'].includes(row.status)) throw QErrors.bookingNotActive();
        const ctx = await this.lockDayOf(q, t, row, now, effects);
        const current = ctx.queue.find((e) => e.bookingId === id);
        if (!current) throw QErrors.bookingNotActive();
        if (current.status === 'in_service') throw QErrors.bookingStarted();
        const offer = row.status === 'offered';
        await this.removeFromQueue(q, ctx, id, offer ? 'expired' : 'cancelled', offer ? 'offer_rejected' : 'customer', effects, {
          reason: offer ? 'offer_released' : 'cancelled_ahead',
          actorKind: 'customer',
          actorId: me.subjectId,
        });
        if (!offer) {
          await insertBookingEvent(q, { bookingId: id, type: 'cancelled', occurredAt: now, actorKind: 'customer', actorId: me.subjectId, reason: 'customer' });
          await writeAudit(q, { actorKind: 'customer', actorId: me.subjectId, action: 'booking.cancelled', targetKind: 'booking', targetId: id, ip, details: { by: 'customer' } });
        }
        return { status: 200, body: await this.dto(q, id) };
      }),
    );
    return unwrap(out);
  }

  async history(t: TenantContext, me: Principal) {
    const { rows } = await t.db.query<BookingRow & { staff_name: string; payment_status: string | null; payment_amount: string | null }>(
      `SELECT x.*, s.name AS staff_name, p.status AS payment_status, p.amount_minor AS payment_amount
         FROM (${BOOKING_SELECT}
                WHERE (b.customer_id = $1
                       -- ق20 / review H2: a linked walk-in record is visible only to an ACTIVE account.
                       OR b.customer_id = (SELECT linked_walk_in_id FROM customers WHERE id = $1 AND status = 'active' AND phone_released_at IS NULL))
                  AND b.status NOT IN ('offered', 'expired')) x
         JOIN staff s ON s.id = x.staff_id
         LEFT JOIN payments p ON p.booking_id = x.id
        ORDER BY x.created_at DESC LIMIT 100`,
      [me.subjectId],
    );
    const dtos = await bookingDtos(t.db, rows);
    return dtos.map((d, i) => ({
      ...d,
      barberName: rows[i]!.staff_name,
      payment: rows[i]!.payment_status ? { status: rows[i]!.payment_status, amountCents: Number(rows[i]!.payment_amount) } : null,
    }));
  }
}

async function resolveServicesOf(q: TenantQueryable, bookingId: string): Promise<ServiceRow[]> {
  const { rows } = await q.query<ServiceRow>(
    `SELECT s.id, bs.name_snapshot AS name, s.base_duration_minutes, s.price_minor, s.active, s.position
       FROM booking_services bs JOIN services s ON s.id = bs.service_id WHERE bs.booking_id = $1 ORDER BY bs.position`,
    [bookingId],
  );
  return rows;
}

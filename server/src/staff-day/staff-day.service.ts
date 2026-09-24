import { Injectable } from '@nestjs/common';
import {
  changeDuration,
  diffProjections,
  findPlacement,
  MINUTE,
  needsNotification,
  pastClosing,
  queueEnd,
} from '@saloni/engine';
import type { Principal } from '../auth/principal';
import { normalizePhone } from '../common/normalize';
import { writeAudit } from '../security/audit';
import { SettingsRepo, type SettingsRow } from '../settings/settings.repository';
import type { TenantContext, TenantQueryable } from '../tenancy/tenant-context';
import { loadBooking, placeBooking, resolveServices, sumMinutes, sumPrice } from '../scheduling/booking-writer';
import { Clock } from '../scheduling/clock';
import {
  type DayCtx,
  emitChange,
  estimateFor,
  loadDay,
  opensAtOn,
  project,
  releaseExpiredOffers,
  resolveShift,
  shiftForDate,
  stateOf,
  stateWire,
} from '../scheduling/day';
import { bookingDtos, type BookingDto } from '../scheduling/dto';
import { QErrors } from '../scheduling/errors';
import { once, unwrap } from '../scheduling/idempotency';
import { PostCommit } from '../scheduling/post-commit';
import { activeServices, currentSeq } from '../scheduling/rows';
import { dailyBreakInShift, type Shift } from '../scheduling/time';

const iso = (t: number | Date | null | undefined) => (t === null || t === undefined ? null : new Date(t).toISOString());

export function staffSettings(s: SettingsRow, callAheadMinutes: number, salon: { timezone: string; currency: string }) {
  return {
    callAheadMinutes,
    etaChangeNotifyMinutes: s.eta_change_notify_minutes,
    overrunAlertPercent: s.overrun_alert_percent,
    offerHoldMinutes: s.offer_hold_minutes,
    maxDisconnectWindowMinutes: s.max_disconnect_window_minutes,
    bookingOpensBeforeMinutes: s.booking_opens_before_minutes,
    heartbeatSeconds: 30,
    offlineAfterSeconds: 90,
    timezone: salon.timezone,
    currency: salon.currency,
  };
}

/** Barber-facing endpoints (api.md "الطاقم"): today, walk-ins, impact preview, payments, heartbeat. */
@Injectable()
export class StaffDayService {
  constructor(
    private readonly clock: Clock,
    private readonly post: PostCommit,
  ) {}

  private async breakList(q: TenantQueryable, tz: string, staffId: string, shift: Shift) {
    const { rows } = await q.query<{
      id: string;
      type: 'rest' | 'prayer' | 'emergency' | 'walk_in_only';
      work_date: string | null;
      start_time: string | null;
      end_time: string | null;
      starts_at: Date | null;
      ends_at: Date | null;
      open: boolean;
    }>(
      `SELECT b.id, b.type, b.work_date::text AS work_date, b.start_time::text AS start_time, b.end_time::text AS end_time,
              b.starts_at, b.ends_at, b.open
         FROM breaks b
        WHERE b.staff_id = $1 AND (b.work_date IS NULL OR (b.starts_at < $3 AND (b.ends_at > $2 OR b.open)))`,
      [staffId, new Date(shift.workStart), new Date(shift.workEnd)],
    );
    const opensAt = (await opensAtOn(q, staffId, shift.workDate)) ?? '00:00';
    return rows
      .map((b) => {
        const iv =
          b.work_date === null
            ? dailyBreakInShift(shift, b.start_time!, b.end_time!, tz, opensAt)
            : { start: b.starts_at!.getTime(), end: b.ends_at!.getTime() };
        return { id: b.id, kind: b.type, start: iso(iv.start)!, end: iso(iv.end)!, open: b.open, recurring: b.work_date === null };
      })
      .sort((a, b) => a.start.localeCompare(b.start));
  }

  async today(t: TenantContext, me: Principal) {
    const now = this.clock.now();
    const settings = await SettingsRepo.get(t.db);
    const shift = await resolveShift(t.db, t.salon.timezone, me.subjectId, now, settings.booking_opens_before_minutes * MINUTE);
    const services = (await activeServices(t.db)).map((s) => ({
      id: s.id,
      name: s.name,
      baseDurationMin: s.base_duration_minutes,
      priceCents: Number(s.price_minor),
      active: s.active,
    }));
    const { rows: me2 } = await t.db.query<{ call_ahead_minutes: number }>('SELECT call_ahead_minutes FROM staff WHERE id = $1', [me.subjectId]);
    const base = {
      services,
      settings: staffSettings(settings, me2[0]?.call_ahead_minutes ?? 20, t.salon),
      serverTime: iso(now)!,
      seq: await currentSeq(t.db),
    };
    if (!shift) return { day: null, queue: [], breaks: [], walkInOnly: [], closingWarnings: [], ...base };
    const ctx = await loadDay(t.db, t.salon, me.subjectId, shift, now, { settings });
    const slots = project(ctx);
    const queue = await bookingDtos(t.db, ctx.rows, new Map(slots.map((s) => [s.bookingId, s])), { includePhone: true });
    const breaks = await this.breakList(t.db, t.salon.timezone, me.subjectId, shift);
    const serveLate = new Set(ctx.rows.filter((r) => r.serve_late).map((r) => r.id));
    return {
      day: {
        workDate: shift.workDate,
        workStart: iso(shift.workStart),
        workEnd: iso(shift.workEnd),
        state: stateWire(ctx.state),
        firstConnectedAt: iso(ctx.dayRow?.first_connected_at),
      },
      queue,
      breaks: breaks.filter((b) => b.kind !== 'walk_in_only').map(({ id, kind, start, end, open }) => ({ id, kind, start, end, open })),
      walkInOnly: breaks.filter((b) => b.kind === 'walk_in_only').map(({ id, start, end }) => ({ id, start, end })),
      // ق24: bookings now projected past closing that still need the barber's decision.
      closingWarnings: pastClosing(ctx.day, slots).filter((id) => !serveLate.has(id)),
      ...base,
    };
  }

  /** Design §4: a heartbeat every 30 s marks the barber connected and records his known work (ق3). */
  async heartbeat(t: TenantContext, me: Principal, body: { deviceSeq: number; queueDigest?: string }) {
    const now = this.clock.now();
    const settings = await SettingsRepo.get(t.db);
    const shift = await resolveShift(t.db, t.salon.timezone, me.subjectId, now, settings.booking_opens_before_minutes * MINUTE);
    if (!shift) return { serverTime: iso(now), seq: await currentSeq(t.db), state: null, workDate: null };
    const out = await this.post.tx(t, async (q, effects) => {
      const ctx = await loadDay(q, t.salon, me.subjectId, shift, now, { lock: true, settings });
      await releaseExpiredOffers(q, ctx, effects);
      const wasOffline = ctx.state.kind === 'offline';
      const knownEnd = queueEnd(ctx.day, ctx.queue.filter((e) => !e.offer), now);
      await q.query(
        `UPDATE barber_days SET state = CASE WHEN $7 THEN 'absent' ELSE 'connected' END,
                first_connected_at = COALESCE(first_connected_at, $2), last_heartbeat_at = $2,
                known_work_end_at = $3, known_work_minutes_at_last_heartbeat = $4,
                -- Kept until the scheduler has sent the one reconciled ق5 notice (design §4 "عند عودة الاتصال").
                offline_since = CASE WHEN $6::timestamptz IS NOT NULL THEN COALESCE(offline_since, $6) ELSE offline_since END,
                last_device_seq = GREATEST(COALESCE(last_device_seq, 0), $5), updated_at = now()
          WHERE id = $1`,
        [
          ctx.dayRow!.id,
          new Date(now),
          new Date(knownEnd),
          Math.max(0, Math.round((knownEnd - now) / MINUTE)),
          body.deviceSeq,
          ctx.state.kind === 'offline' ? new Date(ctx.state.offlineSince) : null,
          ctx.state.kind === 'absent',
        ],
      );
      const newState = stateOf({ ...ctx.dayRow!, first_connected_at: ctx.dayRow!.first_connected_at ?? new Date(now), last_heartbeat_at: new Date(now) }, false, now);
      if (ctx.state.kind !== newState.kind && ctx.state.kind !== 'absent') {
        await emitChange(q, effects, { staffId: me.subjectId, type: 'day_state', entity: 'barber_day', data: { workDate: shift.workDate, state: stateWire(newState), reconnected: wasOffline } });
      }
      return { state: ctx.state.kind === 'absent' ? 'absent_today' : 'connected', reconnected: wasOffline };
    });
    return { serverTime: iso(now), seq: await currentSeq(t.db), workDate: shift.workDate, ...out };
  }

  /**
   * Walk-in (design §3): online only, added to the end of this barber's queue — or into a
   * walk-in-only window (ق33) if it fits there without delaying anyone (ق4). Never for an absent barber.
   */
  async walkIn(t: TenantContext, me: Principal, body: { name: string; phone: string; serviceIds: string[] }, key: string | null, ip: string): Promise<BookingDto> {
    const phone = normalizePhone(body.phone);
    if (!phone) throw QErrors.invalidPhone();
    const out = await this.post.tx(t, (q, effects) =>
      once<BookingDto>(q, { kind: 'staff', id: me.subjectId }, key, 'walk_in', async () => {
        const now = this.clock.now();
        const settings = await SettingsRepo.get(q);
        const shift = await resolveShift(q, t.salon.timezone, me.subjectId, now, settings.booking_opens_before_minutes * MINUTE);
        if (!shift) throw QErrors.notWorkingNow();
        const ctx = await loadDay(q, t.salon, me.subjectId, shift, now, { lock: true, settings });
        await releaseExpiredOffers(q, ctx, effects);
        if (ctx.state.kind === 'absent') throw QErrors.barberAbsent();
        const services = await resolveServices(q, body.serviceIds);
        const customerId = await this.walkInRecord(q, me, body.name.trim(), phone, settings, ip);
        const { durationMs, setKey } = await estimateFor(q, me.subjectId, customerId, body.serviceIds, sumMinutes(services));
        const req = { kind: 'queue' as const, duration: durationMs, walkIn: true };
        const popts = { ...ctx.opts, policy: ctx.policy };
        const windows = ctx.day.breaks.filter((b) => b.kind === 'walk_in_only');
        const inWindow = windows.length ? findPlacement(ctx.day, ctx.queue, now, req, popts) : null;
        const p =
          inWindow && windows.some((w) => inWindow.start >= w.start && inWindow.start < w.end)
            ? inWindow
            : findPlacement(ctx.day, ctx.queue, now, req, { ...popts, appendOnly: true });
        if (!p) throw QErrors.pastClosing();
        const { id, slot } = await placeBooking(
          q,
          ctx,
          {
            customerId,
            source: 'barber',
            kind: 'queue',
            offer: false,
            durationMs,
            setKey,
            services,
            position: p.position,
            idempotencyKey: key,
            actorKind: 'staff',
            actorId: me.subjectId,
          },
          effects,
        );
        const row = (await loadBooking(q, id))!;
        const [dto] = await bookingDtos(q, [row], new Map([[id, slot]]), { includePhone: true });
        return { status: 201, body: dto! };
      }),
    );
    return unwrap(out);
  }

  /** A walk-in customer record (name + phone, ق6). ق20: linked to an app account automatically only when approval is on. */
  private async walkInRecord(q: TenantQueryable, me: Principal, name: string, phone: string, settings: SettingsRow, ip: string): Promise<string> {
    const { rows } = await q.query<{ id: string }>(
      `SELECT id FROM customers WHERE phone = $1 AND password_hash IS NULL AND lower(btrim(name)) = lower($2) ORDER BY created_at LIMIT 1`,
      [phone, name],
    );
    let id = rows[0]?.id;
    if (!id) {
      const ins = await q.query<{ id: string }>(
        `INSERT INTO customers (name, phone, password_hash, status, created_by_staff_id) VALUES ($1, $2, NULL, 'active', $3) RETURNING id`,
        [name, phone, me.subjectId],
      );
      id = ins.rows[0]!.id;
    }
    if (settings.require_account_approval) {
      const { rows: acct } = await q.query<{ id: string }>(
        `UPDATE customers SET linked_walk_in_id = $2, updated_at = now()
          WHERE phone = $1 AND password_hash IS NOT NULL AND linked_walk_in_id IS NULL
            AND NOT EXISTS (SELECT 1 FROM customers a WHERE a.linked_walk_in_id = $2)
          RETURNING id`,
        [phone, id],
      );
      if (acct[0]) {
        await writeAudit(q, {
          actorKind: 'staff', actorId: me.subjectId, action: 'customer.walk_in_linked', targetKind: 'customer', targetId: acct[0].id, ip,
          details: { walkInId: id, automatic: true },
        });
      }
    }
    return id;
  }

  /** ق9/ق24 preview: who is delayed (and by how much), who would pass closing, who must be notified (ق5). */
  async impact(t: TenantContext, me: Principal, body: { bookingId: string; serviceIds: string[] }) {
    const now = this.clock.now();
    const row = await loadBooking(t.db, body.bookingId);
    if (!row || (row.staff_id !== me.subjectId && me.role !== 'manager')) throw QErrors.bookingNotFound();
    const services = await resolveServices(t.db, body.serviceIds);
    const shift = await shiftForDate(t.db, t.salon.timezone, row.staff_id, row.work_date);
    const ctx: DayCtx = await loadDay(t.db, t.salon, row.staff_id, shift, now);
    if (!ctx.byId.has(row.id)) throw QErrors.bookingNotActive();
    const { durationMs } = await estimateFor(t.db, row.staff_id, row.customer_id, body.serviceIds, sumMinutes(services));
    const before = project(ctx);
    const after = project(ctx, changeDuration(ctx.queue, row.id, durationMs));
    const past = new Set(pastClosing(ctx.day, after));
    const pastBefore = new Set(pastClosing(ctx.day, before));
    const changes = diffProjections(before, after).map((d) => {
      const r = ctx.byId.get(d.bookingId)!;
      const ref = (r.last_shown_expected_start ?? r.original_expected_start)?.getTime() ?? d.before;
      return {
        bookingId: d.bookingId,
        customerName: r.customer_name,
        before: iso(d.before),
        after: iso(d.after),
        deltaMin: Math.round(d.delta / MINUTE),
        pastClosing: past.has(d.bookingId),
        notify: r.source === 'app' && needsNotification(ref, d.after, ctx.policy),
      };
    });
    const oldPrice = (await bookingDtos(t.db, [row]))[0]!.priceCents;
    return {
      bookingId: row.id,
      oldDurationMin: Math.round((row.estimated_duration_seconds ?? 0) / 60),
      newDurationMin: Math.round(durationMs / MINUTE),
      oldPriceCents: oldPrice,
      newPriceCents: sumPrice(services),
      changes,
      pastClosing: [...past].map((id) => ({
        bookingId: id,
        customerName: ctx.byId.get(id)?.customer_name ?? null,
        end: iso(after.find((s) => s.bookingId === id)!.end),
        newlyPastClosing: !pastBefore.has(id),
      })),
      workEnd: iso(ctx.day.workEnd),
    };
  }

  /** Payments awaiting confirmation (any day) and those confirmed in the last 24 h. Barbers see their own. */
  async payments(t: TenantContext, me: Principal) {
    const now = this.clock.now();
    const { rows } = await t.db.query<{
      id: string;
      booking_id: string;
      amount_minor: string;
      status: string;
      confirmed_by_staff_id: string | null;
      confirmed_at: Date | null;
      created_at: Date;
      staff_id: string;
      customer_name: string;
      work_date: string;
      actual_end: Date | null;
    }>(
      `SELECT p.id, p.booking_id, p.amount_minor, p.status, p.confirmed_by_staff_id, p.confirmed_at, p.created_at,
              b.staff_id, c.name AS customer_name, b.work_date::text AS work_date, b.actual_end
         FROM payments p JOIN bookings b ON b.id = p.booking_id JOIN customers c ON c.id = b.customer_id
        WHERE ($1::uuid IS NULL OR b.staff_id = $1)
          AND (p.status = 'awaiting_confirmation' OR p.confirmed_at > $2)
        ORDER BY (p.status = 'confirmed'), p.created_at DESC LIMIT 200`,
      [me.role === 'manager' ? null : me.subjectId, new Date(now - 24 * 60 * MINUTE)],
    );
    return rows.map((r) => ({
      id: r.id,
      bookingId: r.booking_id,
      amountCents: Number(r.amount_minor),
      status: r.status,
      confirmedBy: r.confirmed_by_staff_id,
      confirmedAt: iso(r.confirmed_at),
      barberId: r.staff_id,
      customerName: r.customer_name,
      workDate: r.work_date,
      finishedAt: iso(r.actual_end),
      createdAt: iso(r.created_at),
    }));
  }
}

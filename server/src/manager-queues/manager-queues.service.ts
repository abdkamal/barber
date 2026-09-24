import { Injectable } from '@nestjs/common';
import { insertAt, MINUTE, placeWithBarber, type QueueEntry, remove } from '@saloni/engine';
import type { Principal } from '../auth/principal';
import { NotificationService } from '../notifications/notification.service';
import { Texts } from '../notifications/texts';
import { writeAudit } from '../security/audit';
import { SettingsRepo, type SettingsRow } from '../settings/settings.repository';
import type { TenantContext, TenantQueryable } from '../tenancy/tenant-context';
import { emitBooking, loadBooking, sumMinutes } from '../scheduling/booking-writer';
import { Clock } from '../scheduling/clock';
import {
  commitQueue,
  type DayCtx,
  estimateFor,
  insertBookingEvent,
  loadDay,
  lockDays,
  operationalShift,
  project,
  shiftForDate,
  stateWire,
  updateReference,
  workingStaff,
} from '../scheduling/day';
import { bookingDtos, type BookingDto } from '../scheduling/dto';
import { QErrors } from '../scheduling/errors';
import { once, unwrap } from '../scheduling/idempotency';
import { PostCommit } from '../scheduling/post-commit';
import { currentSeq, type ServiceRow } from '../scheduling/rows';
import { currentShift } from '../scheduling/time';

const iso = (t: number | Date | null | undefined) => (t === null || t === undefined ? null : new Date(t).toISOString());

interface Alternative {
  barberId: string;
  barberName: string;
  start: string;
  end: string;
}

/**
 * Manager view of every barber's queue today and the manual transfer of a booking to another
 * barber (ق25, design §3 "نقل لحلاق آخر"): manager only, keeps the booking, inserted at the new
 * barber under ق4/ق19, customer notified (§8), recorded (booking_events + audit_log).
 */
@Injectable()
export class ManagerQueuesService {
  constructor(
    private readonly clock: Clock,
    private readonly post: PostCommit,
    private readonly notifications: NotificationService,
  ) {}

  async queues(t: TenantContext) {
    const now = this.clock.now();
    const settings = await SettingsRepo.get(t.db);
    const lookahead = settings.booking_opens_before_minutes * MINUTE;
    const barbers = [];
    for (const s of await workingStaff(t.db)) {
      const shift = await operationalShift(t.db, t.salon.timezone, s.id, now, lookahead, s.schedules);
      if (!shift) {
        barbers.push({ id: s.id, name: s.name, role: s.role, day: null, accepting: false, queue: [] });
        continue;
      }
      const ctx = await loadDay(t.db, t.salon, s.id, shift, now, { settings, staff: s });
      const slots = new Map(project(ctx).map((x) => [x.bookingId, x]));
      // Tentative offers (ق13) hold a place but are not bookings yet — not listed (their time shows as a gap).
      const rows = ctx.rows.filter((r) => r.status !== 'offered');
      barbers.push({
        id: s.id,
        name: s.name,
        role: s.role,
        day: {
          workDate: shift.workDate,
          workStart: iso(shift.workStart),
          workEnd: iso(shift.workEnd),
          state: stateWire(ctx.state),
          firstConnectedAt: iso(ctx.dayRow?.first_connected_at),
        },
        accepting: ctx.gate.accepts,
        queue: await bookingDtos(t.db, rows, slots, { includePhone: true }),
      });
    }
    return { serverTime: iso(now)!, seq: await currentSeq(t.db), barbers };
  }

  async transfer(t: TenantContext, me: Principal, id: string, toBarberId: string, key: string | null, ip: string): Promise<BookingDto> {
    const out = await this.post.tx(t, (q, effects) =>
      once<BookingDto>(q, { kind: 'staff', id: me.subjectId }, key, `transfer:${id}`, async () => {
        const now = this.clock.now();
        const row = await loadBooking(q, id);
        if (!row || row.status === 'offered' || row.status === 'expired') throw QErrors.bookingNotFound();
        if (row.status === 'in_service') throw QErrors.bookingStarted();
        if (row.status !== 'waiting' && row.status !== 'called') throw QErrors.bookingNotActive();
        if (row.staff_id === toBarberId) throw QErrors.sameBarber();

        const settings = await SettingsRepo.get(q);
        const all = await workingStaff(q);
        const target = all.find((s) => s.id === toBarberId);
        if (!target) {
          const exists = await q.query('SELECT 1 FROM staff WHERE id = $1 AND active', [toBarberId]);
          throw exists.rowCount ? QErrors.barberNotWorking() : QErrors.barberNotFound();
        }
        const targetShift = currentShift(target.schedules, t.salon.timezone, now, settings.booking_opens_before_minutes * MINUTE);
        if (!targetShift || targetShift.workDate !== row.work_date) throw QErrors.barberNotWorking();
        const sourceShift = await shiftForDate(q, t.salon.timezone, row.staff_id, row.work_date);

        // §5.13: lock both barber days, always in id order (no deadlock with other transfers/bookings).
        // Both days are locked before either releases its expired offers (no change emitted before all locks).
        const locked = await lockDays(
          q,
          t.salon,
          [
            { staffId: row.staff_id, shift: sourceShift },
            { staffId: target.id, shift: targetShift, staff: target },
          ],
          now,
          settings,
          effects,
        );
        const src: DayCtx = locked.get(`${row.staff_id}|${sourceShift.workDate}`)!;
        const dst: DayCtx = locked.get(`${target.id}|${targetShift.workDate}`)!;

        // Re-check under the lock: the barber may have started the service meanwhile.
        const entry = src.queue.find((e) => e.bookingId === id);
        if (!entry || entry.offer) throw QErrors.bookingNotActive();
        if (entry.status === 'in_service') throw QErrors.bookingStarted();

        if (dst.state.kind === 'absent') throw QErrors.barberAbsent();
        if (!dst.gate.accepts) throw QErrors.barberUnavailable();

        const services = await servicesOf(q, id);
        const { durationMs } = await estimateFor(q, target.id, row.customer_id, services.map((s) => s.id), sumMinutes(services));
        const req = { kind: entry.kind, requestedAt: entry.requestedAt };
        const placement = placeWithBarber({ day: dst.day, queue: dst.queue, state: dst.state, duration: durationMs }, now, req, dst.policy);
        if (!placement) {
          const alternatives = await this.alternatives(q, t, all, settings, row.staff_id, target.id, row.customer_id, services, req, row.work_date, now);
          throw QErrors.transferNoSlot({ nearest: alternatives[0] ?? null, alternatives });
        }

        const before = src.rows.find((r) => r.id === id)!;
        const beforeSlot = project(src).find((s) => s.bookingId === id);
        // A pending change-time offer (§5.12) for this booking would move it back — release it.
        const staleOffers = src.rows.filter((r) => r.status === 'offered' && r.replaces_booking_id === id).map((r) => r.id);
        if (staleOffers.length) {
          await q.query(
            `UPDATE bookings SET status = 'expired', queue_position = NULL, cancel_reason = 'offer_replaced', updated_at = now() WHERE id = ANY($1::uuid[])`,
            [staleOffers],
          );
        }
        let srcNext = remove(src.queue, id);
        for (const o of staleOffers) srcNext = remove(srcNext, o);
        await commitQueue(q, src, srcNext, { reason: 'transferred_ahead', primary: [id, ...staleOffers], effects, actorKind: 'staff', actorId: me.subjectId });
        for (const o of staleOffers) await emitBooking(q, src, o, 'booking_removed', effects);

        // Design §3: the booking keeps its state; a called customer waits to be called again by the new barber.
        const moved: QueueEntry = { ...entry, status: 'waiting', estimatedDuration: durationMs, offer: false };
        await q.query(
          `UPDATE bookings SET staff_id = $2, called_at = NULL, last_change_reason = 'transferred', last_change_at = $3, updated_at = now() WHERE id = $1`,
          [id, target.id, new Date(now)],
        );
        const slots = await commitQueue(q, dst, insertAt(dst.queue, placement.position, moved), {
          reason: 'transferred',
          primary: [id],
          effects,
          actorKind: 'staff',
          actorId: me.subjectId,
        });
        const slot = slots.find((s) => s.bookingId === id)!;
        // The notice below tells the customer the new time: it becomes his ق5 reference.
        await updateReference(q, id, slot.start, { reset: true });
        await insertBookingEvent(q, {
          bookingId: id,
          type: 'transferred',
          payload: {
            fromBarberId: row.staff_id,
            toBarberId: target.id,
            previousStatus: entry.status,
            before: beforeSlot ? iso(beforeSlot.start) : iso(before.projected_start),
            after: iso(slot.start),
          },
          occurredAt: now,
          actorKind: 'staff',
          actorId: me.subjectId,
          reason: 'transferred',
        });
        await writeAudit(q, {
          actorKind: 'staff',
          actorId: me.subjectId,
          action: 'booking.transferred',
          targetKind: 'booking',
          targetId: id,
          ip,
          details: { fromBarberId: row.staff_id, toBarberId: target.id },
        });
        await emitBooking(q, src, id, 'booking_removed', effects);
        await emitBooking(q, dst, id, 'booking_created', effects, slot);
        await this.notifications.toCustomer(q, effects, row.customer_id, {
          type: 'transferred',
          bookingId: id,
          text: Texts.transferred(target.name, slot.start, t.salon.timezone),
          data: { eta: iso(slot.start)!, barberId: target.id },
        });
        const fresh = (await loadBooking(q, id))!;
        const [dto] = await bookingDtos(q, [fresh], new Map([[id, slot]]), { includePhone: true });
        return { status: 200, body: dto! };
      }),
    );
    return unwrap(out);
  }

  /** Where else the booking would fit now (read-only, advisory): earliest start first. */
  private async alternatives(
    q: TenantQueryable,
    t: TenantContext,
    all: Awaited<ReturnType<typeof workingStaff>>,
    settings: SettingsRow,
    sourceId: string,
    targetId: string,
    customerId: string,
    services: ServiceRow[],
    req: { kind: 'queue' | 'requested'; requestedAt?: number },
    workDate: string,
    now: number,
  ): Promise<Alternative[]> {
    const out: Alternative[] = [];
    for (const s of all) {
      if (s.id === sourceId || s.id === targetId) continue;
      const shift = currentShift(s.schedules, t.salon.timezone, now, settings.booking_opens_before_minutes * MINUTE);
      if (!shift || shift.workDate !== workDate) continue;
      const ctx = await loadDay(q, t.salon, s.id, shift, now, { settings, staff: s });
      if (!ctx.gate.accepts) continue;
      const { durationMs } = await estimateFor(q, s.id, customerId, services.map((x) => x.id), sumMinutes(services));
      const p = placeWithBarber({ day: ctx.day, queue: ctx.queue, state: ctx.state, duration: durationMs }, now, req, ctx.policy);
      if (p) out.push({ barberId: s.id, barberName: s.name, start: iso(p.start)!, end: iso(p.end)! });
    }
    return out.sort((a, b) => a.start.localeCompare(b.start));
  }
}

async function servicesOf(q: TenantQueryable, bookingId: string): Promise<ServiceRow[]> {
  const { rows } = await q.query<ServiceRow>(
    `SELECT s.id, bs.name_snapshot AS name, s.base_duration_minutes, s.price_minor, s.active, s.position
       FROM booking_services bs JOIN services s ON s.id = bs.service_id WHERE bs.booking_id = $1 ORDER BY bs.position`,
    [bookingId],
  );
  return rows;
}

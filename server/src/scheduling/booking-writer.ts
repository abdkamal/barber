import { insertAt, type ProjectedSlot, type QueueEntry } from '@saloni/engine';
import type { TenantQueryable } from '../tenancy/tenant-context';
import { commitQueue, type DayCtx, type Effects, emitChange, insertBookingEvent } from './day';
import { bookingDtos } from './dto';
import { QErrors } from './errors';
import { BOOKING_SELECT, type BookingRow, type ServiceRow } from './rows';

/** Active services by id, in the requested order; any unknown/inactive/duplicate id is an error. */
export async function resolveServices(q: TenantQueryable, ids: string[]): Promise<ServiceRow[]> {
  if (!ids.length || new Set(ids).size !== ids.length) throw QErrors.serviceUnavailable();
  const { rows } = await q.query<ServiceRow>(
    'SELECT id, name, base_duration_minutes, price_minor, active, position FROM services WHERE id = ANY($1::uuid[]) AND active',
    [ids],
  );
  if (rows.length !== ids.length) throw QErrors.serviceUnavailable();
  const by = new Map(rows.map((r) => [r.id, r]));
  return ids.map((id) => by.get(id)!);
}

export const sumPrice = (s: ServiceRow[]) => s.reduce((a, r) => a + Number(r.price_minor), 0);
export const sumMinutes = (s: ServiceRow[]) => s.reduce((a, r) => a + r.base_duration_minutes, 0);

export async function replaceBookingServices(q: TenantQueryable, bookingId: string, services: ServiceRow[]): Promise<void> {
  await q.query('DELETE FROM booking_services WHERE booking_id = $1', [bookingId]);
  let i = 0;
  for (const s of services) {
    await q.query(
      `INSERT INTO booking_services (booking_id, service_id, name_snapshot, price_minor, duration_minutes_snapshot, position)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [bookingId, s.id, s.name, s.price_minor, s.base_duration_minutes, i++],
    );
  }
}

export interface NewBooking {
  customerId: string;
  source: 'app' | 'barber';
  kind: 'queue' | 'requested';
  requestedAt?: number;
  offer: boolean;
  offerExpiresAt?: number;
  durationMs: number;
  setKey: string;
  services: ServiceRow[];
  position: number;
  replaces?: string | null;
  idempotencyKey?: string | null;
  actorKind: 'staff' | 'customer';
  actorId: string;
}

/**
 * Inserts a booking (or a held offer) at `position` in the locked day and persists the queue.
 * The original expected time and the "last shown" reference (ق5) are the placement's start.
 */
export async function placeBooking(q: TenantQueryable, ctx: DayCtx, b: NewBooking, effects: Effects): Promise<{ id: string; slot: ProjectedSlot }> {
  const { rows } = await q.query<{ id: string }>(
    `INSERT INTO bookings (customer_id, staff_id, kind, requested_at, status, queue_position, source, work_date,
                           idempotency_key, offer_expires_at, estimated_duration_seconds, service_set_key, replaces_booking_id)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13) RETURNING id`,
    [
      b.customerId,
      ctx.staff.id,
      b.kind,
      b.kind === 'requested' ? new Date(b.requestedAt!) : null,
      b.offer ? 'offered' : 'waiting',
      b.position,
      b.source,
      ctx.shift.workDate,
      b.offer ? null : b.idempotencyKey ?? null,
      b.offer ? new Date(b.offerExpiresAt!) : null,
      Math.round(b.durationMs / 1000),
      b.setKey,
      b.replaces ?? null,
    ],
  );
  const id = rows[0]!.id;
  await replaceBookingServices(q, id, b.services);
  const entry: QueueEntry = {
    bookingId: id,
    kind: b.kind,
    requestedAt: b.kind === 'requested' ? b.requestedAt : undefined,
    status: 'waiting',
    estimatedDuration: b.durationMs,
    walkIn: b.source === 'barber',
    offer: b.offer,
  };
  const slots = await commitQueue(q, ctx, insertAt(ctx.queue, b.position, entry), {
    reason: b.source === 'barber' ? 'walk_in' : 'booked',
    primary: [id],
    effects,
    actorKind: b.actorKind,
    actorId: b.actorId,
  });
  const slot = slots.find((s) => s.bookingId === id)!;
  await q.query('UPDATE bookings SET original_expected_start = $2, last_shown_expected_start = $2, told_expected_start = $2 WHERE id = $1', [id, new Date(slot.start)]);
  await insertBookingEvent(q, {
    bookingId: id,
    type: b.offer ? 'offered' : 'created',
    payload: { start: new Date(slot.start).toISOString(), position: b.position, kind: b.kind, source: b.source, replaces: b.replaces ?? null },
    occurredAt: ctx.now,
    actorKind: b.actorKind,
    actorId: b.actorId,
    reason: b.offer ? 'offer' : 'booked',
  });
  await emitBooking(q, ctx, id, b.offer ? 'booking_offered' : 'booking_created', effects, slot);
  return { id, slot };
}

/** Change-feed entry carrying the full booking DTO. */
export async function emitBooking(q: TenantQueryable, ctx: DayCtx, id: string, type: string, effects: Effects, slot?: ProjectedSlot): Promise<void> {
  const { rows } = await q.query<BookingRow>(`${BOOKING_SELECT} WHERE b.id = $1`, [id]);
  const [dto] = await bookingDtos(q, rows, slot ? new Map([[id, slot]]) : undefined, { includePhone: rows[0]?.source === 'barber' });
  await emitChange(q, effects, { staffId: ctx.staff.id, type, bookingId: id, data: dto as unknown as Record<string, unknown> });
}

export async function loadBooking(q: TenantQueryable, id: string): Promise<BookingRow | null> {
  const { rows } = await q.query<BookingRow>(`${BOOKING_SELECT} WHERE b.id = $1`, [id]);
  return rows[0] ?? null;
}

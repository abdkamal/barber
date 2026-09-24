import { markCalled, MINUTE, type QueueEntry, selectToCall } from '@saloni/engine';
import { NotificationService } from '../notifications/notification.service';
import { Texts } from '../notifications/texts';
import type { TenantQueryable } from '../tenancy/tenant-context';
import { emitBooking } from './booking-writer';
import { type DayCtx, type Effects, insertBookingEvent, project, updateReference } from './day';

/**
 * Design §5.5: at most one in service and one called; the next waiting customer is called once
 * his projected start is within the barber's lead time, or immediately after a postponement (ق21).
 * Returns the queue with the call applied (not yet persisted) and the called booking id.
 */
export function nextCall(ctx: DayCtx, queue: QueueEntry[], immediate: boolean): { queue: QueueEntry[]; calledId: string | null } {
  if (ctx.state.kind === 'absent') return { queue, calledId: null };
  const slots = project(ctx, queue);
  const id = selectToCall(queue, slots, ctx.now, ctx.staff.call_ahead_minutes * MINUTE, { immediate });
  return id ? { queue: markCalled(queue, id), calledId: id } : { queue, calledId: null };
}

/** Records a call made by `nextCall` (after the queue was committed): timestamp, event, notice. */
export async function recordCall(
  q: TenantQueryable,
  ctx: DayCtx,
  notifications: NotificationService,
  effects: Effects,
  id: string,
  immediate: boolean,
): Promise<void> {
  const slot = project(ctx).find((s) => s.bookingId === id);
  await q.query('UPDATE bookings SET called_at = $2 WHERE id = $1', [id, new Date(ctx.now)]);
  // The call tells the customer a time: his new ق5 reference (an advance is remembered for ق23).
  if (slot) await updateReference(q, id, slot.start);
  await insertBookingEvent(q, {
    bookingId: id,
    type: 'called',
    payload: { eta: slot ? new Date(slot.start).toISOString() : null, immediate },
    occurredAt: ctx.now,
    actorKind: 'system',
    reason: immediate ? 'after_postponement' : 'lead_time',
  });
  const row = ctx.byId.get(id);
  if (row && slot) {
    await notifications.toCustomer(q, effects, row.customer_id, {
      type: 'called',
      bookingId: id,
      highPriority: true,
      text: Texts.called(ctx.staff.name, slot.start, ctx.salon.timezone),
    });
  }
  await emitBooking(q, ctx, id, 'booking_called', effects, slot);
}

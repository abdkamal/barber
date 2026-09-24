import { Injectable } from '@nestjs/common';
import { MINUTE, type ProjectedSlot } from '@saloni/engine';
import { SettingsRepo } from '../settings/settings.repository';
import type { TenantContext, TenantQueryable } from '../tenancy/tenant-context';
import { Clock } from '../scheduling/clock';
import {
  commitQueue,
  type DayCtx,
  dbStateOf,
  type Effects,
  emitChange,
  loadDay,
  lockDays,
  operationalShift,
  project,
  stateOf,
  stateWire,
} from '../scheduling/day';
import { PostCommit } from '../scheduling/post-commit';
import type { ReasonCode } from '../scheduling/reasons';
import type { Shift } from '../scheduling/time';

export interface AffectedDay {
  staffId: string;
  shift: Shift;
}

/**
 * Review I6: manager changes to absences and breaks run like every other queue mutation — in the
 * transaction that holds the affected barber days locked (§5.13), then the queue is re-projected
 * and committed with a reason (ق5 bookkeeping), the devices get a change (day_state /
 * breaks_changed) and the scheduler is poked (PostCommit).
 */
@Injectable()
export class ScheduleChangesService {
  constructor(
    private readonly clock: Clock,
    private readonly post: PostCommit,
  ) {}

  now(): number {
    return this.clock.now();
  }

  /** The operational day of each staff member (C1) — the day a recurring break or today's dated break affects. */
  async currentDays(q: TenantQueryable, t: TenantContext, staffIds: string[]): Promise<AffectedDay[]> {
    const settings = await SettingsRepo.get(q);
    const out: AffectedDay[] = [];
    for (const id of staffIds) {
      const shift = await operationalShift(q, t.salon.timezone, id, this.clock.now(), settings.booking_opens_before_minutes * MINUTE);
      if (shift) out.push({ staffId: id, shift });
    }
    return out;
  }

  /**
   * The staff member's day for `workDate` when it is his operational day (C1) — the only day with a
   * live queue and devices following it; changes to other dates need no queue work (and must not
   * send the devices a queue/day state of another date).
   */
  async dayOf(q: TenantQueryable, t: TenantContext, staffId: string, workDate: string): Promise<AffectedDay[]> {
    const [cur] = await this.currentDays(q, t, [staffId]);
    return cur && cur.shift.workDate === workDate ? [cur] : [];
  }

  /**
   * Runs `mutate` with every affected day locked (consistent order, before any change is emitted),
   * then re-projects and commits each day. `afterDay` may emit per-day changes.
   */
  run<T>(
    t: TenantContext,
    days: (q: TenantQueryable) => Promise<AffectedDay[]>,
    mutate: (q: TenantQueryable, effects: Effects, locked: Map<string, DayCtx>) => Promise<T>,
    o: { reason: ReasonCode; actorId: string; afterDay?: (q: TenantQueryable, effects: Effects, ctx: DayCtx) => Promise<void> },
  ): Promise<T> {
    return this.post.tx(t, async (q, effects) => {
      const now = this.clock.now();
      const settings = await SettingsRepo.get(q);
      const affected = await days(q);
      const locked = await lockDays(q, t.salon, affected, now, settings, effects);
      const before = new Map<string, ProjectedSlot[]>([...locked].map(([k, ctx]) => [k, project(ctx)]));
      const out = await mutate(q, effects, locked);
      for (const [k, ctx] of locked) {
        const fresh = await loadDay(q, t.salon, ctx.staff.id, ctx.shift, now, { lock: true, settings, staff: ctx.staff });
        await commitQueue(q, fresh, fresh.queue, { reason: o.reason, effects, actorKind: 'staff', actorId: o.actorId, before: before.get(k) });
        if (o.afterDay) await o.afterDay(q, effects, fresh);
      }
      return out;
    });
  }

  /** Persists the day state after an absence was added/removed and tells the barber's devices. */
  async syncDayState(q: TenantQueryable, effects: Effects, ctx: DayCtx): Promise<void> {
    const { rows } = await q.query('SELECT 1 FROM absences WHERE staff_id = $1 AND work_date = $2', [ctx.staff.id, ctx.shift.workDate]);
    const state = stateOf(ctx.dayRow, rows.length > 0, ctx.now);
    await q.query('UPDATE barber_days SET state = $2, updated_at = now() WHERE id = $1', [ctx.dayRow!.id, dbStateOf(state)]);
    await emitChange(q, effects, {
      staffId: ctx.staff.id,
      type: 'day_state',
      entity: 'barber_day',
      data: { workDate: ctx.shift.workDate, state: stateWire(state) },
    });
  }

  async breaksChanged(q: TenantQueryable, effects: Effects, ctx: DayCtx): Promise<void> {
    await emitChange(q, effects, { staffId: ctx.staff.id, type: 'breaks_changed', entity: 'break', data: { workDate: ctx.shift.workDate } });
  }
}

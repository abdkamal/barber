import { Inject, Injectable, Logger, OnApplicationBootstrap, OnApplicationShutdown } from '@nestjs/common';
import { MINUTE, needsNotification, overrunAlert } from '@saloni/engine';
import { APP_CONFIG, AppConfig } from '../config/config';
import { PoolManager } from '../db/pools';
import { DirectoryRepo } from '../directory/directory.repository';
import { NotificationService } from '../notifications/notification.service';
import { Texts } from '../notifications/texts';
import { SettingsRepo, type SettingsRow } from '../settings/settings.repository';
import type { TenantContext, TenantQueryable } from '../tenancy/tenant-context';
import { TenantResolver } from '../tenancy/tenant-resolver.service';
import { nextCall, recordCall } from '../scheduling/calling';
import { Clock } from '../scheduling/clock';
import {
  commitQueue,
  dbStateOf,
  type Effects,
  emitChange,
  HEARTBEAT_TIMEOUT_MS,
  insertBookingEvent,
  loadDay,
  project,
  releaseExpiredOffers,
  stateWire,
  workingStaff,
} from '../scheduling/day';
import { PostCommit } from '../scheduling/post-commit';
import { reasonText, type ReasonCode } from '../scheduling/reasons';
import type { StaffInfo } from '../scheduling/rows';
import { currentShift, type Shift } from '../scheduling/time';

const TICK_MS = 1_000;
/** Longest pause for a salon with a working barber (ETA drift, ق5, is checked at least this often). */
const MAX_IDLE_MS = 60 * 1000;
/** Salons without any shift running are looked at rarely. */
const QUIET_MS = 10 * MINUTE;
const SALON_LIST_TTL_MS = 60 * 1000;

/**
 * One in-process loop for every salon (single server instance, ق8). Each salon has a next-due
 * time computed from its own state (offer expiry, next call, heartbeat timeout, shift start,
 * overrun) — idle salons are not queried every tick. Any queue change pokes its salon.
 * Per salon it: expires offers (ق13), updates barber day states (§4), alerts the manager when a
 * barber has not connected at shift start (ق32), calls customers (§5.5), reminds the barber at
 * 100% of the estimate (ق27), sends the mandatory >30 min notices (ق5/ق23) only while the barber
 * is live — one reconciled notice after a reconnect — and dispatches pending notifications.
 */
@Injectable()
export class SchedulerService implements OnApplicationBootstrap, OnApplicationShutdown {
  private readonly logger = new Logger('Scheduler');
  private readonly due = new Map<string, number>();
  private salons: Array<{ id: string }> = [];
  private salonsAt = 0;
  private timer?: NodeJS.Timeout;
  private running = false;
  private stopped = false;
  private active: string | null = null;
  private pokedDuringRun = false;

  constructor(
    @Inject(APP_CONFIG) private readonly config: AppConfig,
    private readonly pools: PoolManager,
    private readonly resolver: TenantResolver,
    private readonly clock: Clock,
    private readonly post: PostCommit,
    private readonly notifications: NotificationService,
  ) {}

  get enabled(): boolean {
    const v = process.env.SCHEDULER_ENABLED;
    if (v !== undefined) return ['1', 'true', 'yes', 'on'].includes(v.toLowerCase());
    return this.config.env !== 'test';
  }

  onApplicationBootstrap(): void {
    this.post.onPoke((id) => this.poke(id));
    if (this.enabled) this.schedule();
  }

  onApplicationShutdown(): void {
    this.stopped = true;
    if (this.timer) clearTimeout(this.timer);
  }

  poke(salonId: string): void {
    this.due.set(salonId, 0);
    if (this.active === salonId) this.pokedDuringRun = true;
  }

  nextDue(salonId: string): number | undefined {
    return this.due.get(salonId);
  }

  private schedule(): void {
    if (this.stopped) return;
    this.timer = setTimeout(() => {
      void this.tick().finally(() => this.schedule());
    }, TICK_MS);
    this.timer.unref();
  }

  /** One pass over the salons that are due. */
  async tick(): Promise<void> {
    if (this.running) return;
    this.running = true;
    try {
      const now = this.clock.now();
      if (now - this.salonsAt > SALON_LIST_TTL_MS) {
        this.salons = await DirectoryRepo.list(this.pools.directoryPool(), 'active');
        this.salonsAt = now;
      }
      for (const s of this.salons) {
        if ((this.due.get(s.id) ?? 0) > now) continue;
        const t = await this.resolver.fromVerifiedToken(s.id).catch(() => null);
        if (!t || t.salon.status !== 'active') continue;
        this.active = s.id;
        this.pokedDuringRun = false;
        try {
          const next = await this.runSalon(t);
          // A change committed meanwhile (by a request or by this run) gets one more pass right away.
          this.due.set(s.id, this.pokedDuringRun ? now + TICK_MS : next);
        } catch (e) {
          this.logger.warn(`salon ${t.salon.code}: ${(e as Error).message}`);
          this.due.set(s.id, now + 30_000);
        } finally {
          this.active = null;
        }
      }
    } catch (e) {
      this.logger.warn(`tick failed: ${(e as Error).message}`);
    } finally {
      this.running = false;
    }
  }

  /** Runs all due work for one salon now; returns when it should run next. */
  async runSalon(t: TenantContext): Promise<number> {
    const now = this.clock.now();
    const settings = await SettingsRepo.get(t.db);
    let next = now + QUIET_MS;
    for (const s of await workingStaff(t.db)) {
      const shift = currentShift(s.schedules, t.salon.timezone, now, settings.booking_opens_before_minutes * MINUTE);
      if (!shift) continue;
      next = Math.min(next, await this.post.tx(t, (q, effects) => this.runBarber(q, effects, t, s, shift, settings, now)));
    }
    const pending = await t.db.query("SELECT 1 FROM notifications WHERE status = 'pending' LIMIT 1");
    if (pending.rowCount) {
      await this.notifications.dispatch(t);
      next = Math.min(next, now + 30_000); // retry failed sends
    }
    return Math.max(next, now + TICK_MS);
  }

  private async runBarber(
    q: TenantQueryable,
    effects: Effects,
    t: TenantContext,
    staff: StaffInfo,
    shift: Shift,
    settings: SettingsRow,
    now: number,
  ): Promise<number> {
    const ctx = await loadDay(q, t.salon, staff.id, shift, now, { lock: true, settings, staff });
    await releaseExpiredOffers(q, ctx, effects);
    let due = now + MAX_IDLE_MS;
    const day = ctx.dayRow!;

    // Day state bookkeeping (§4): connected → disconnected after 90 s without a heartbeat.
    const dbState = dbStateOf(ctx.state);
    if (day.state !== dbState) {
      await q.query(
        `UPDATE barber_days SET state = $2,
                offline_since = CASE WHEN $2 = 'disconnected' THEN COALESCE(offline_since, last_heartbeat_at) ELSE offline_since END,
                updated_at = now() WHERE id = $1`,
        [day.id, dbState],
      );
      await emitChange(q, effects, { staffId: staff.id, type: 'day_state', entity: 'barber_day', data: { workDate: shift.workDate, state: stateWire(ctx.state) } });
    }
    if (ctx.state.kind === 'online') due = Math.min(due, day.last_heartbeat_at!.getTime() + HEARTBEAT_TIMEOUT_MS + 1000);

    // ق32: the manager is alerted from the start of the barber's shift if his app has not connected.
    if (ctx.state.kind === 'not_connected') {
      const alertAt = shift.workStart + settings.barber_not_connected_alert_minutes * MINUTE;
      if (now >= alertAt && !day.not_connected_alerted_at) {
        await this.notifications.toManagers(q, effects, {
          type: 'barber_not_connected',
          text: Texts.barberNotConnected(staff.name, shift.workStart, t.salon.timezone),
          dedupeKey: `not_connected:${staff.id}:${shift.workDate}`,
          data: { barberId: staff.id },
        });
        await q.query('UPDATE barber_days SET not_connected_alerted_at = $2 WHERE id = $1', [day.id, new Date(now)]);
      } else if (now < alertAt) {
        due = Math.min(due, alertAt);
      }
    }

    // Offers: wake up when the next one expires.
    for (const r of ctx.rows) if (r.status === 'offered' && r.offer_expires_at) due = Math.min(due, r.offer_expires_at.getTime());

    // §5.5 calling (continues on estimates while the barber is offline or not yet connected).
    const call = nextCall(ctx, ctx.queue, false);
    if (call.calledId) {
      await commitQueue(q, ctx, call.queue, { reason: 'queue_moved', primary: [call.calledId], effects });
      await recordCall(q, ctx, this.notifications, effects, call.calledId, false);
    } else if (!ctx.queue.some((e) => e.status === 'called')) {
      const slots = project(ctx);
      const i = ctx.queue.findIndex((e) => e.status === 'waiting' && !e.offer);
      if (i >= 0) due = Math.min(due, slots[i]!.start - staff.call_ahead_minutes * MINUTE);
    }

    // ق27: remind the barber once the service reaches its estimate (never ended automatically).
    const cur = ctx.queue.find((e) => e.status === 'in_service');
    const curRow = cur ? ctx.byId.get(cur.bookingId) : undefined;
    if (cur && curRow && !curRow.overrun_alerted_at && cur.actualStart !== undefined) {
      if (overrunAlert(cur.actualStart, cur.estimatedDuration, now, ctx.policy)) {
        await this.notifications.toStaff(q, effects, staff.id, {
          type: 'overrun',
          bookingId: cur.bookingId,
          text: Texts.overrun(curRow.customer_name),
        });
        await q.query('UPDATE bookings SET overrun_alerted_at = $2 WHERE id = $1', [cur.bookingId, new Date(now)]);
        await insertBookingEvent(q, { bookingId: cur.bookingId, type: 'overrun_alert', occurredAt: now, actorKind: 'system', reason: 'service_overrun' });
      } else {
        due = Math.min(due, cur.actualStart + Math.ceil(cur.estimatedDuration * ctx.policy.overrunAlertRatio));
      }
    }

    await this.mandatoryNotices(q, effects, ctx, day.offline_since !== null);
    return due;
  }

  /**
   * ق5/ق23 (§5.9): the expected start moved more than the margin — earlier or later — from the
   * last time the customer was shown → one notice, and that time becomes the new reference.
   * Suppressed while the barber is not live (§4); after a reconnect this yields one reconciled notice.
   */
  private async mandatoryNotices(q: TenantQueryable, effects: Effects, ctx: Awaited<ReturnType<typeof loadDay>>, reconnecting: boolean): Promise<void> {
    const slots = project(ctx);
    const byId = new Map(slots.map((s) => [s.bookingId, s]));
    // Keep stored projections fresh (drift from overruns/time passing) without logging each minute.
    for (const e of ctx.queue) {
      const r = ctx.byId.get(e.bookingId)!;
      const s = byId.get(e.bookingId)!;
      if (!r.projected_start || Math.abs(r.projected_start.getTime() - s.start) >= MINUTE) {
        await q.query('UPDATE bookings SET projected_start = $2, projected_end = $3 WHERE id = $1', [e.bookingId, new Date(s.start), new Date(s.end)]);
      }
    }
    if (ctx.state.kind !== 'online') return;
    const overrunning = ctx.queue.some((e) => e.status === 'in_service' && e.actualStart !== undefined && ctx.now > e.actualStart + e.estimatedDuration);
    for (const e of ctx.queue) {
      if (e.offer || e.status === 'in_service') continue;
      const r = ctx.byId.get(e.bookingId)!;
      if (r.source !== 'app') continue;
      const ref = (r.last_shown_expected_start ?? r.original_expected_start)?.getTime();
      const s = byId.get(e.bookingId)!;
      if (ref === undefined || !needsNotification(ref, s.start, ctx.policy)) continue;
      const delta = s.start - ref;
      const code: ReasonCode = reconnecting
        ? 'reconnected'
        : delta > 0 && overrunning
          ? 'service_overrun'
          : ((r.last_change_reason as ReasonCode | null) ?? (delta > 0 ? 'service_overrun' : 'queue_moved'));
      const text = reasonText(code) ?? reasonText('queue_moved')!;
      await this.notifications.toCustomer(q, effects, r.customer_id, {
        type: 'eta_changed',
        bookingId: r.id,
        text: Texts.etaChanged(s.start, delta, text, ctx.salon.timezone),
        data: { eta: new Date(s.start).toISOString() },
      });
      await q.query('UPDATE bookings SET last_shown_expected_start = $2 WHERE id = $1', [r.id, new Date(s.start)]);
      await insertBookingEvent(q, {
        bookingId: r.id,
        type: 'eta_notified',
        payload: { reference: new Date(ref).toISOString(), eta: new Date(s.start).toISOString(), deltaSec: Math.round(delta / 1000) },
        occurredAt: ctx.now,
        actorKind: 'system',
        reason: code,
      });
    }
    if (reconnecting) await q.query('UPDATE barber_days SET offline_since = NULL WHERE id = $1', [ctx.dayRow!.id]);
  }
}

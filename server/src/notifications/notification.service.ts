import { Inject, Injectable, Logger } from '@nestjs/common';
import type { Effects } from '../scheduling/day';
import type { TenantContext, TenantQueryable } from '../tenancy/tenant-context';
import { NOTIFIER, type Notifier } from './notifier';
import type { Text } from './texts';

export type NotificationType =
  | 'booking_confirmed'
  | 'called'
  | 'eta_changed'
  | 'postponed'
  | 'no_show'
  | 'cancelled_closing'
  | 'transferred'
  | 'overrun'
  | 'account_pending'
  | 'barber_not_connected'
  | 'barber_absent'
  | 'sync_conflict'
  | 'base_duration_suspect';

export interface NotificationInput {
  type: NotificationType;
  bookingId?: string | null;
  text: Text;
  highPriority?: boolean;
  /** At most one notification per key (e.g. one "not connected" alert per barber and day). */
  dedupeKey?: string;
  data?: Record<string, string>;
}

const MAX_ATTEMPTS = 5;

/**
 * Notifications are written to the salon DB inside the business transaction (an outbox), then
 * dispatched after commit. Every notification is kept with its delivery status.
 */
@Injectable()
export class NotificationService {
  private readonly logger = new Logger('Notifications');
  private readonly running = new Map<string, Promise<void>>();

  constructor(@Inject(NOTIFIER) readonly notifier: Notifier) {}

  /** To an app customer (walk-in records have no app — nothing is queued). */
  async toCustomer(q: TenantQueryable, effects: Effects, customerId: string, n: NotificationInput): Promise<boolean> {
    const { rows } = await q.query('SELECT 1 FROM customers WHERE id = $1 AND password_hash IS NOT NULL', [customerId]);
    if (!rows.length) return false;
    return this.enqueue(q, effects, 'customer', customerId, n);
  }

  async toStaff(q: TenantQueryable, effects: Effects, staffId: string, n: NotificationInput): Promise<boolean> {
    return this.enqueue(q, effects, 'staff', staffId, n);
  }

  async toManagers(q: TenantQueryable, effects: Effects, n: NotificationInput): Promise<number> {
    const { rows } = await q.query<{ id: string }>("SELECT id FROM staff WHERE role = 'manager' AND active ORDER BY created_at");
    let count = 0;
    for (const m of rows) {
      if (await this.enqueue(q, effects, 'staff', m.id, { ...n, dedupeKey: n.dedupeKey ? `${n.dedupeKey}:${m.id}` : undefined })) count++;
    }
    return count;
  }

  private async enqueue(q: TenantQueryable, effects: Effects, kind: 'staff' | 'customer', id: string, n: NotificationInput): Promise<boolean> {
    const data = { type: n.type, ...(n.bookingId ? { bookingId: n.bookingId } : {}), ...(n.data ?? {}) };
    const { rowCount } = await q.query(
      `INSERT INTO notifications (recipient_kind, recipient_id, type, booking_id, title, body, data, high_priority, dedupe_key)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) ON CONFLICT DO NOTHING`,
      [kind, id, n.type, n.bookingId ?? null, n.text.title, n.text.body, JSON.stringify(data), !!n.highPriority, n.dedupeKey ?? null],
    );
    if (rowCount) effects.notifications = true;
    return (rowCount ?? 0) > 0;
  }

  /** Sends pending notifications of one salon (serialised per salon). */
  dispatch(t: TenantContext): Promise<void> {
    const prev = this.running.get(t.salonId) ?? Promise.resolve();
    const next = prev.then(() => this.dispatchNow(t)).catch((e) => this.logger.warn(`dispatch failed for ${t.salon.code}: ${(e as Error).message}`));
    this.running.set(t.salonId, next);
    void next.finally(() => {
      if (this.running.get(t.salonId) === next) this.running.delete(t.salonId);
    });
    return next;
  }

  /** Waits for in-flight dispatches (tests, shutdown). */
  async idle(): Promise<void> {
    while (this.running.size) await Promise.all([...this.running.values()]);
  }

  private async dispatchNow(t: TenantContext): Promise<void> {
    const { rows } = await t.db.query<{
      id: string;
      recipient_kind: 'staff' | 'customer';
      recipient_id: string;
      title: string;
      body: string;
      data: Record<string, string>;
      high_priority: boolean;
      attempts: number;
    }>(
      `SELECT id, recipient_kind, recipient_id, title, body, data, high_priority, attempts
         FROM notifications WHERE status = 'pending' ORDER BY created_at LIMIT 200`,
    );
    for (const n of rows) {
      if (!this.notifier.enabled) {
        await this.finish(t, n.id, 'disabled', null);
        continue;
      }
      const { rows: devices } = await t.db.query<{ id: string; fcm_token: string }>(
        `SELECT id, fcm_token FROM devices
          WHERE owner_kind = $1 AND owner_id = $2 AND fcm_token IS NOT NULL AND notifications_allowed`,
        [n.recipient_kind, n.recipient_id],
      );
      if (!devices.length) {
        await this.finish(t, n.id, 'no_device', null);
        continue;
      }
      let ok = false;
      let error: string | null = null;
      for (const d of devices) {
        const r = await this.notifier.send({ token: d.fcm_token, title: n.title, body: n.body, data: n.data, highPriority: n.high_priority });
        if (r === 'ok') ok = true;
        else if (r === 'invalid_token') await t.db.query('UPDATE devices SET fcm_token = NULL, updated_at = now() WHERE id = $1', [d.id]);
        else error = 'send_failed';
      }
      if (ok) await this.finish(t, n.id, 'sent', null);
      else if (!error) await this.finish(t, n.id, 'no_device', null);
      else if (n.attempts + 1 >= MAX_ATTEMPTS) await this.finish(t, n.id, 'failed', error);
      else await t.db.query('UPDATE notifications SET attempts = attempts + 1, last_error = $2 WHERE id = $1', [n.id, error]);
    }
  }

  private async finish(t: TenantContext, id: string, status: string, error: string | null): Promise<void> {
    await t.db.query(
      `UPDATE notifications SET status = $2, attempts = attempts + 1, last_error = $3,
              sent_at = CASE WHEN $2 = 'sent' THEN now() ELSE sent_at END
        WHERE id = $1 AND status = 'pending'`,
      [id, status, error],
    );
  }
}

import { Injectable } from '@nestjs/common';
import { NotificationService } from '../notifications/notification.service';
import type { TenantContext, TenantQueryable } from '../tenancy/tenant-context';
import { ChangeBus } from './change-bus';
import { Effects } from './day';
import { currentSeq } from './rows';

const RETRYABLE = new Set(['40P01', '40001']); // deadlock, serialization failure

/**
 * Runs a queue transaction (retrying on deadlock) and then its after-commit effects: WebSocket
 * push of the new change seq, notification dispatch, and a nudge to the scheduler.
 */
@Injectable()
export class PostCommit {
  private readonly pokers = new Set<(salonId: string) => void>();

  constructor(
    private readonly bus: ChangeBus,
    private readonly notifications: NotificationService,
  ) {}

  onPoke(fn: (salonId: string) => void): void {
    this.pokers.add(fn);
  }

  async tx<T>(t: TenantContext, fn: (q: TenantQueryable, effects: Effects) => Promise<T>): Promise<T> {
    for (let attempt = 1; ; attempt++) {
      const effects = new Effects();
      try {
        const out = await t.db.tx((q) => fn(q, effects));
        await this.after(t, effects);
        return out;
      } catch (e) {
        if (attempt < 4 && RETRYABLE.has((e as { code?: string }).code ?? '')) continue;
        throw e;
      }
    }
  }

  async after(t: TenantContext, effects: Effects): Promise<void> {
    if (effects.staff.size) {
      const seq = await currentSeq(t.db);
      this.bus.publish({ salonId: t.salonId, staffIds: [...effects.staff], seq });
    }
    if (effects.notifications) void this.notifications.dispatch(t);
    for (const p of this.pokers) p(t.salonId);
  }
}

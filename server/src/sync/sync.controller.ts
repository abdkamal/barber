import { Body, Controller, Get, HttpCode, Inject, Post, Query } from '@nestjs/common';
import { APP_CONFIG, type AppConfig } from '../config/config';
import { Errors } from '../common/errors';
import { RateLimiter } from '../security/rate-limiter';
import { z } from 'zod';
import { Roles } from '../auth/auth.decorators';
import type { Principal } from '../auth/principal';
import { ZodPipe } from '../common/zod.pipe';
import type { TenantContext } from '../tenancy/tenant-context';
import { CurrentPrincipal, Tenant } from '../tenancy/tenant.decorator';
import { SyncService } from './sync.service';

/** One device event — shared with the ق40 recovery upload (`recovery.controller.ts`). */
export const Event = z.object({
  id: z.string().uuid(),
  deviceSeq: z.number().int().min(0),
  type: z.string().min(1).max(40),
  bookingId: z.string().uuid().nullable().optional(),
  occurredAt: z.string().datetime({ offset: true }),
  approximate: z.boolean().optional().default(false),
  payload: z.record(z.string(), z.unknown()).optional().default({}),
});
export const Batch = z.object({ events: z.array(Event).max(200) }).strict();
const PullQuery = z.object({ since: z.coerce.number().int().min(0).default(0) });

/** Staff sync (design §6, api.md). */
@Controller('sync')
@Roles('barber', 'manager')
export class SyncController {
  /** Per staff account (the IP limiter runs before authentication and cannot key by account). */
  private readonly limiter = new RateLimiter();

  constructor(
    private readonly sync: SyncService,
    @Inject(APP_CONFIG) private readonly config: AppConfig,
  ) {}

  /** Returns one outcome per event, in the order sent: applied / duplicate / rejected (+ reason). */
  @Post('events')
  @HttpCode(200)
  push(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Body(new ZodPipe(Batch)) body: z.infer<typeof Batch>) {
    // Review M4: a per-account budget for event pushes.
    if (this.config.rateLimits.enabled) {
      const wait = this.limiter.hit(`${t.salonId}|${me.subjectId}`, this.config.rateLimits.sync.account);
      if (wait > 0) throw Errors.tooManyRequests(wait);
    }
    return this.sync.applyBatch(t, me, body.events);
  }

  @Get()
  pull(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Query(new ZodPipe(PullQuery)) q: z.infer<typeof PullQuery>) {
    return this.sync.pull(t, me, q.since);
  }
}

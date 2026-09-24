import { Body, Controller, Get, HttpCode, Post, Query } from '@nestjs/common';
import { z } from 'zod';
import { Roles } from '../auth/auth.decorators';
import type { Principal } from '../auth/principal';
import { ZodPipe } from '../common/zod.pipe';
import type { TenantContext } from '../tenancy/tenant-context';
import { CurrentPrincipal, Tenant } from '../tenancy/tenant.decorator';
import { SyncService } from './sync.service';

const Event = z.object({
  id: z.string().uuid(),
  deviceSeq: z.number().int().min(0),
  type: z.string().min(1).max(40),
  bookingId: z.string().uuid().nullable().optional(),
  occurredAt: z.string().datetime({ offset: true }),
  approximate: z.boolean().optional().default(false),
  payload: z.record(z.string(), z.unknown()).optional().default({}),
});
const Batch = z.object({ events: z.array(Event).max(200) }).strict();
const PullQuery = z.object({ since: z.coerce.number().int().min(0).default(0) });

/** Staff sync (design §6, api.md). */
@Controller('sync')
@Roles('barber', 'manager')
export class SyncController {
  constructor(private readonly sync: SyncService) {}

  /** Returns one outcome per event, in the order sent: applied / duplicate / rejected (+ reason). */
  @Post('events')
  @HttpCode(200)
  push(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Body(new ZodPipe(Batch)) body: z.infer<typeof Batch>) {
    return this.sync.applyBatch(t, me, body.events);
  }

  @Get()
  pull(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Query(new ZodPipe(PullQuery)) q: z.infer<typeof PullQuery>) {
    return this.sync.pull(t, me, q.since);
  }
}

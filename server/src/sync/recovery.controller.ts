import { Body, Controller, Get, HttpCode, Inject, Param, ParseUUIDPipe, Post, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import { z } from 'zod';
import { Roles } from '../auth/auth.decorators';
import type { Principal } from '../auth/principal';
import { Errors } from '../common/errors';
import { ZodPipe } from '../common/zod.pipe';
import { APP_CONFIG, type AppConfig } from '../config/config';
import { clientIp } from '../security/client-ip';
import { RateLimiter } from '../security/rate-limiter';
import { StaffRepo } from '../staff/staff.repository';
import type { TenantContext } from '../tenancy/tenant-context';
import { CurrentPrincipal, Tenant } from '../tenancy/tenant.decorator';
import { RecoveryRepo } from './recovery.repository';
import { Batch } from './sync.controller';
import { SyncService } from './sync.service';

const idParam = new ParseUUIDPipe({ exceptionFactory: () => Errors.notFound() });
const ListQuery = z.object({ status: z.enum(['pending', 'all']).default('pending') }).strict();

/**
 * ق40 — offline events of a suspended staff account (manager only; tenant from the verified token).
 * The manager uploads the pending events from that device; the recovered events are then listed
 * for review until acknowledged.
 */
@Controller('manager')
@Roles('manager')
export class RecoveryController {
  /** Per manager account, the same budget as a device's sync pushes. */
  private readonly limiter = new RateLimiter();

  constructor(
    private readonly sync: SyncService,
    @Inject(APP_CONFIG) private readonly config: AppConfig,
  ) {}

  @Post('staff/:id/recover-events')
  @HttpCode(200)
  async recover(
    @Tenant() t: TenantContext,
    @CurrentPrincipal() me: Principal,
    @Param('id', idParam) id: string,
    @Body(new ZodPipe(Batch)) body: z.infer<typeof Batch>,
    @Req() req: Request,
  ) {
    if (this.config.rateLimits.enabled) {
      const wait = this.limiter.hit(`${t.salonId}|${me.subjectId}`, this.config.rateLimits.sync.account);
      if (wait > 0) throw Errors.tooManyRequests(wait);
    }
    const target = await StaffRepo.findById(t.db, id);
    if (!target) throw Errors.notFound();
    if (target.active || !target.suspended_at) {
      throw Errors.conflict('ACCOUNT_NOT_SUSPENDED', 'هذا الحساب غير موقوف — يرفع صاحبه إجراءاته بنفسه عند الدخول');
    }
    return this.sync.recoverBatch(t, me, { id: target.id, role: target.role, suspendedAt: target.suspended_at }, body.events, clientIp(req));
  }

  @Get('recovered-events')
  list(@Tenant() t: TenantContext, @Query(new ZodPipe(ListQuery)) q: z.infer<typeof ListQuery>) {
    return RecoveryRepo.list(t.db, q.status === 'all');
  }

  @Post('recovered-events/:id/ack')
  @HttpCode(200)
  async ack(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Param('id', idParam) id: string, @Req() req: Request) {
    const ok = await RecoveryRepo.acknowledge(t, id, me.subjectId, clientIp(req));
    if (!ok) throw Errors.notFound();
    return { ok: true };
  }
}

import { Body, Controller, Get, Headers, HttpCode, Post, Req } from '@nestjs/common';
import type { Request } from 'express';
import { z } from 'zod';
import { Roles } from '../auth/auth.decorators';
import type { Principal } from '../auth/principal';
import { ZodPipe } from '../common/zod.pipe';
import { idempotencyKey } from '../scheduling/idempotency';
import { clientIp } from '../security/client-ip';
import type { TenantContext } from '../tenancy/tenant-context';
import { CurrentPrincipal, Tenant } from '../tenancy/tenant.decorator';
import { StaffDayService } from './staff-day.service';

const uuid = z.string().uuid();
const WalkIn = z
  .object({
    name: z.string().trim().min(1).max(80),
    phone: z.string().min(1).max(32),
    serviceIds: z.array(uuid).min(1).max(10),
  })
  .strict();
const Impact = z.object({ bookingId: uuid, serviceIds: z.array(uuid).min(1).max(10) }).strict();
const Heartbeat = z.object({ deviceSeq: z.number().int().min(0), queueDigest: z.string().max(200).optional() }).strict();

/** Barber endpoints (api.md "الطاقم (الحلاق)"). Managers who also cut hair use them for their own queue. */
@Controller()
@Roles('barber', 'manager')
export class StaffDayController {
  constructor(private readonly staff: StaffDayService) {}

  @Get('staff/today')
  today(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal) {
    return this.staff.today(t, me);
  }

  @Post('heartbeat')
  @HttpCode(200)
  heartbeat(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Body(new ZodPipe(Heartbeat)) body: z.infer<typeof Heartbeat>) {
    return this.staff.heartbeat(t, me, body);
  }

  @Post('staff/walk-ins')
  walkIn(
    @Tenant() t: TenantContext,
    @CurrentPrincipal() me: Principal,
    @Body(new ZodPipe(WalkIn)) body: z.infer<typeof WalkIn>,
    @Req() req: Request,
    @Headers('idempotency-key') key?: string,
  ) {
    return this.staff.walkIn(t, me, body, idempotencyKey(key), clientIp(req));
  }

  @Post('staff/impact')
  @HttpCode(200)
  impact(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Body(new ZodPipe(Impact)) body: z.infer<typeof Impact>) {
    return this.staff.impact(t, me, body);
  }

  @Get('staff/payments')
  payments(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal) {
    return this.staff.payments(t, me);
  }
}

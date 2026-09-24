import { Body, Controller, Get, Headers, HttpCode, Param, ParseUUIDPipe, Post, Req } from '@nestjs/common';
import type { Request } from 'express';
import { z } from 'zod';
import { Roles } from '../auth/auth.decorators';
import type { Principal } from '../auth/principal';
import { Errors } from '../common/errors';
import { ZodPipe } from '../common/zod.pipe';
import { idempotencyKey } from '../scheduling/idempotency';
import { clientIp } from '../security/client-ip';
import type { TenantContext } from '../tenancy/tenant-context';
import { CurrentPrincipal, Tenant } from '../tenancy/tenant.decorator';
import { ManagerQueuesService } from './manager-queues.service';

const Transfer = z.object({ toBarberId: z.string().uuid() }).strict();
const idParam = new ParseUUIDPipe({ exceptionFactory: () => Errors.notFound() });

/** Manager: all queues today and manual transfer between barbers (api.md "المدير" → الطوابير, ق25). */
@Controller('manager')
@Roles('manager')
export class ManagerQueuesController {
  constructor(private readonly svc: ManagerQueuesService) {}

  @Get('queues')
  queues(@Tenant() t: TenantContext) {
    return this.svc.queues(t);
  }

  @Post('bookings/:id/transfer')
  @HttpCode(200)
  transfer(
    @Tenant() t: TenantContext,
    @CurrentPrincipal() me: Principal,
    @Param('id', idParam) id: string,
    @Body(new ZodPipe(Transfer)) body: z.infer<typeof Transfer>,
    @Req() req: Request,
    @Headers('idempotency-key') key?: string,
  ) {
    return this.svc.transfer(t, me, id, body.toBarberId, idempotencyKey(key), clientIp(req));
  }
}

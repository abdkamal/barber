import { Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, Query, Req } from '@nestjs/common';
import type { Request } from 'express';
import { z } from 'zod';
import { Roles } from '../auth/auth.decorators';
import { PasswordResetService } from '../auth/password-reset.service';
import type { Principal } from '../auth/principal';
import { SessionsRepo } from '../auth/sessions';
import { Errors } from '../common/errors';
import { ZodPipe } from '../common/zod.pipe';
import { writeAudit } from '../security/audit';
import { clientIp } from '../security/client-ip';
import { RateLimit } from '../security/rate-limit.guard';
import type { TenantContext } from '../tenancy/tenant-context';
import { CurrentPrincipal, Tenant } from '../tenancy/tenant.decorator';
import { CustomersRepo } from './customers.repository';

const ListQuery = z.object({
  status: z.enum(['pending', 'active', 'suspended']).optional(),
  limit: z.coerce.number().int().min(1).max(200).default(100),
  offset: z.coerce.number().int().min(0).default(0),
});

const uuid = new ParseUUIDPipe({ version: '4', exceptionFactory: () => Errors.notFound() });

/** Customer account administration (manager only). */
@Controller('manager/customers')
@Roles('manager')
export class CustomersController {
  constructor(private readonly resets: PasswordResetService) {}

  @Get()
  list(@Tenant() t: TenantContext, @Query(new ZodPipe(ListQuery)) q: z.infer<typeof ListQuery>) {
    return CustomersRepo.list(t.db, q.status, q.limit, q.offset);
  }

  /** Approves a pending account (or reinstates a suspended one). */
  @Post(':id/approve')
  @HttpCode(200)
  approve(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Param('id', uuid) id: string, @Req() req: Request) {
    return this.setStatus(t, me, id, 'active', clientIp(req));
  }

  @Post(':id/suspend')
  @HttpCode(200)
  suspend(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Param('id', uuid) id: string, @Req() req: Request) {
    return this.setStatus(t, me, id, 'suspended', clientIp(req));
  }

  @Post(':id/reset-code')
  @HttpCode(200)
  @RateLimit({ name: 'sensitive' })
  async resetCode(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Param('id', uuid) id: string, @Req() req: Request) {
    const c = await CustomersRepo.findAccountById(t.db, id);
    if (!c) throw Errors.notFound();
    return this.resets.issue(t, { kind: 'customer', id }, { kind: 'staff', staffId: me.subjectId }, clientIp(req));
  }

  private setStatus(t: TenantContext, me: Principal, id: string, status: 'active' | 'suspended', ip: string) {
    return t.db.tx(async (q) => {
      const before = await CustomersRepo.findAccountById(q, id);
      if (!before) throw Errors.notFound();
      const suspending = status === 'suspended';
      const c = await CustomersRepo.setStatus(q, id, status, suspending);
      if (suspending) await SessionsRepo.revokeAllFor(q, 'customer', id, 'suspended');
      await writeAudit(q, {
        actorKind: 'staff', actorId: me.subjectId, action: suspending ? 'customer.suspended' : 'customer.approved',
        targetKind: 'customer', targetId: id, ip, details: { from: before.status },
      });
      return c;
    });
  }
}

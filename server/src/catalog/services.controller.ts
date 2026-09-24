import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Post, Put, Req } from '@nestjs/common';
import type { Request } from 'express';
import { z } from 'zod';
import { Roles } from '../auth/auth.decorators';
import type { Principal } from '../auth/principal';
import { Errors, MAX_PRICE_MINOR, MAX_SERVICE_MINUTES } from '../common/errors';
import { ZodPipe } from '../common/zod.pipe';
import { writeAudit } from '../security/audit';
import { clientIp } from '../security/client-ip';
import type { TenantContext } from '../tenancy/tenant-context';
import { CurrentPrincipal, Tenant } from '../tenancy/tenant.decorator';
import { ServiceRow, ServicesRepo } from './services.repository';

const CreateService = z.object({
  name: z.string().trim().min(1).max(80),
  durationMinutes: z.number().int().min(1).max(MAX_SERVICE_MINUTES),
  price: z.number().int().min(0).max(MAX_PRICE_MINOR),
});
const UpdateService = z
  .object({
    name: z.string().trim().min(1).max(80).optional(),
    durationMinutes: z.number().int().min(1).max(MAX_SERVICE_MINUTES).optional(),
    price: z.number().int().min(0).max(MAX_PRICE_MINOR).optional(),
    active: z.boolean().optional(),
    position: z.number().int().min(0).max(10_000).optional(),
  })
  .strict();

const uuid = new ParseUUIDPipe({ version: '4', exceptionFactory: () => Errors.notFound() });

function toDto(r: ServiceRow) {
  return {
    id: r.id,
    name: r.name,
    durationMinutes: r.base_duration_minutes,
    price: Number(r.price_minor),
    active: r.active,
    position: r.position,
  };
}

function isForeignKeyViolation(e: unknown): boolean {
  return (e as { code?: string })?.code === '23503';
}

/** Bookable services (design §2), manager only. Catalog items of kind "service" link to these. */
@Controller('manager/services')
@Roles('manager')
export class ServicesController {
  @Get()
  async list(@Tenant() t: TenantContext) {
    return (await ServicesRepo.list(t.db)).map(toDto);
  }

  @Post()
  async create(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Body(new ZodPipe(CreateService)) body: z.infer<typeof CreateService>, @Req() req: Request) {
    return t.db.tx(async (q) => {
      const s = await ServicesRepo.insert(q, { name: body.name, durationMinutes: body.durationMinutes, priceMinor: body.price });
      await writeAudit(q, { actorKind: 'staff', actorId: me.subjectId, action: 'service.created', targetKind: 'service', targetId: s.id, ip: clientIp(req) });
      return toDto(s);
    });
  }

  @Put(':id')
  async update(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Param('id', uuid) id: string, @Body(new ZodPipe(UpdateService)) body: z.infer<typeof UpdateService>, @Req() req: Request) {
    return t.db.tx(async (q) => {
      const s = await ServicesRepo.update(q, id, { name: body.name, durationMinutes: body.durationMinutes, priceMinor: body.price, active: body.active, position: body.position });
      if (!s) throw Errors.notFound();
      await writeAudit(q, { actorKind: 'staff', actorId: me.subjectId, action: 'service.updated', targetKind: 'service', targetId: id, ip: clientIp(req), details: { changed: Object.keys(body) } });
      return toDto(s);
    });
  }

  @Delete(':id')
  @HttpCode(200)
  async remove(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Param('id', uuid) id: string, @Req() req: Request) {
    try {
      return await t.db.tx(async (q) => {
        const ok = await ServicesRepo.delete(q, id);
        if (!ok) throw Errors.notFound();
        await writeAudit(q, { actorKind: 'staff', actorId: me.subjectId, action: 'service.deleted', targetKind: 'service', targetId: id, ip: clientIp(req) });
        return { ok: true };
      });
    } catch (e) {
      if (isForeignKeyViolation(e)) {
        throw Errors.conflict('SERVICE_IN_USE', 'هذه الخدمة مستخدمة في حجوزات أو الكتالوج — يمكنك إيقافها بدل حذفها');
      }
      throw e;
    }
  }
}

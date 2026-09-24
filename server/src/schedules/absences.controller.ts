import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Post, Req } from '@nestjs/common';
import type { Request } from 'express';
import { z } from 'zod';
import { Roles } from '../auth/auth.decorators';
import type { Principal } from '../auth/principal';
import { Errors } from '../common/errors';
import { ZodPipe } from '../common/zod.pipe';
import { writeAudit } from '../security/audit';
import { clientIp } from '../security/client-ip';
import { StaffRepo } from '../staff/staff.repository';
import type { TenantContext } from '../tenancy/tenant-context';
import { CurrentPrincipal, Tenant } from '../tenancy/tenant.decorator';
import { AbsenceRow, AbsencesRepo } from './schedules.repository';

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const CreateAbsence = z
  .object({
    staffId: z.string().uuid(),
    workDate: z.string().regex(DATE_RE),
    reason: z.string().trim().max(300).nullable().optional(),
  })
  .strict();

const uuid = new ParseUUIDPipe({ version: '4', exceptionFactory: () => Errors.notFound() });

function toDto(r: AbsenceRow) {
  return { id: r.id, staffId: r.staff_id, workDate: r.work_date, reason: r.reason };
}

/** "Not working today" (design §4, ق26): stops queue assignment for the barber on that work day. */
@Controller('manager/absences')
@Roles('manager')
export class AbsencesController {
  @Get()
  async list(@Tenant() t: TenantContext) {
    return (await AbsencesRepo.list(t.db)).map(toDto);
  }

  @Post()
  async create(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Body(new ZodPipe(CreateAbsence)) body: z.infer<typeof CreateAbsence>, @Req() req: Request) {
    return t.db.tx(async (q) => {
      const staff = await StaffRepo.findById(q, body.staffId);
      if (!staff) throw Errors.validation([{ path: 'staffId', code: 'not_found' }]);
      const row = await AbsencesRepo.insert(q, body.staffId, body.workDate, body.reason ?? null, me.subjectId);
      await writeAudit(q, { actorKind: 'staff', actorId: me.subjectId, action: 'absence.recorded', targetKind: 'staff', targetId: body.staffId, ip: clientIp(req), details: { workDate: body.workDate } });
      return toDto(row);
    });
  }

  @Delete(':id')
  @HttpCode(200)
  async remove(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Param('id', uuid) id: string, @Req() req: Request) {
    return t.db.tx(async (q) => {
      const ok = await AbsencesRepo.delete(q, id);
      if (!ok) throw Errors.notFound();
      await writeAudit(q, { actorKind: 'staff', actorId: me.subjectId, action: 'absence.removed', targetKind: 'absence', targetId: id, ip: clientIp(req) });
      return { ok: true };
    });
  }
}

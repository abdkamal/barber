import { Body, Controller, Delete, Get, HttpCode, Param, Put, Query, Req } from '@nestjs/common';
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
import { SchedulesRepo, WorkScheduleRow } from './schedules.repository';

const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;
const time = () => z.string().regex(TIME_RE, 'invalid_time');

const UpsertSchedule = z
  .object({
    staffId: z.string().uuid().nullable(), // null = salon-wide default for this weekday
    weekday: z.number().int().min(0).max(6),
    opensAt: time(),
    closesAt: time(),
  })
  .strict()
  .refine((b) => b.opensAt !== b.closesAt, { message: 'opensAt must differ from closesAt', path: ['closesAt'] });

function toDto(r: WorkScheduleRow) {
  return { staffId: r.staff_id, weekday: r.weekday, opensAt: r.opens_at.slice(0, 5), closesAt: r.closes_at.slice(0, 5) };
}

/**
 * Weekly working hours (design §2, ق30): a salon-wide default per weekday, overridden per barber.
 * `closesAt <= opensAt` means the shift crosses midnight — accepted as-is (engine/reports handle it).
 */
@Controller('manager/schedules')
@Roles('manager')
export class SchedulesController {
  @Get()
  async list(@Tenant() t: TenantContext) {
    return (await SchedulesRepo.list(t.db)).map(toDto);
  }

  @Put()
  async upsert(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Body(new ZodPipe(UpsertSchedule)) body: z.infer<typeof UpsertSchedule>, @Req() req: Request) {
    return t.db.tx(async (q) => {
      if (body.staffId) {
        const staff = await StaffRepo.findById(q, body.staffId);
        if (!staff) throw Errors.validation([{ path: 'staffId', code: 'not_found' }]);
      }
      const row = await SchedulesRepo.upsert(q, body.staffId, body.weekday, `${body.opensAt}:00`, `${body.closesAt}:00`);
      await writeAudit(q, {
        actorKind: 'staff', actorId: me.subjectId, action: 'schedule.upserted', targetKind: 'work_schedule',
        targetId: body.staffId, ip: clientIp(req), details: { weekday: body.weekday, opensAt: body.opensAt, closesAt: body.closesAt },
      });
      return toDto(row);
    });
  }

  @Delete(':weekday')
  @HttpCode(200)
  async remove(
    @Tenant() t: TenantContext,
    @CurrentPrincipal() me: Principal,
    @Param('weekday') weekdayRaw: string,
    @Query('staffId') staffIdRaw: string | undefined,
    @Req() req: Request,
  ) {
    const weekday = Number(weekdayRaw);
    if (!Number.isInteger(weekday) || weekday < 0 || weekday > 6) throw Errors.validation([{ path: 'weekday', code: 'invalid' }]);
    const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (staffIdRaw !== undefined && !UUID_RE.test(staffIdRaw)) throw Errors.validation([{ path: 'staffId', code: 'invalid' }]);
    const staffId = staffIdRaw;
    return t.db.tx(async (q) => {
      const ok = await SchedulesRepo.deleteOne(q, staffId ?? null, weekday);
      if (!ok) throw Errors.notFound();
      await writeAudit(q, { actorKind: 'staff', actorId: me.subjectId, action: 'schedule.removed', targetKind: 'work_schedule', targetId: staffId ?? null, ip: clientIp(req), details: { weekday } });
      return { ok: true };
    });
  }
}

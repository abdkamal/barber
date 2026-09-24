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
import type { TenantQueryable, TenantContext } from '../tenancy/tenant-context';
import { CurrentPrincipal, Tenant } from '../tenancy/tenant.decorator';
import { datedBreaksOverlap, recurringBreaksOverlap } from './break-overlap';
import { BreakRow, BreaksRepo } from './schedules.repository';

const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const BREAK_TYPES = ['rest', 'prayer', 'emergency', 'walk_in_only'] as const;

const CreateBreak = z
  .object({
    staffId: z.union([z.string().uuid(), z.literal('all')]),
    type: z.enum(BREAK_TYPES),
    // Recurring daily break (salon-local time-of-day):
    startTime: z.string().regex(TIME_RE).optional(),
    endTime: z.string().regex(TIME_RE).optional(),
    // Dated break (specific work day, absolute instants — e.g. prayer times, an emergency):
    workDate: z.string().regex(DATE_RE).optional(),
    startsAt: z.string().datetime().optional(),
    endsAt: z.string().datetime().optional(),
  })
  .strict()
  .refine(
    (b) => {
      const recurring = Boolean(b.startTime && b.endTime);
      const dated = Boolean(b.workDate && b.startsAt && b.endsAt);
      return recurring !== dated;
    },
    { message: 'either {startTime,endTime} (recurring) or {workDate,startsAt,endsAt} (dated), not both' },
  )
  .refine((b) => !b.startTime || b.startTime !== b.endTime, { message: 'startTime must differ from endTime' })
  .refine((b) => !b.startsAt || !b.endsAt || new Date(b.endsAt) > new Date(b.startsAt), { message: 'endsAt must be after startsAt' });

function toDto(r: BreakRow) {
  return {
    id: r.id,
    staffId: r.staff_id,
    type: r.type,
    recurring: r.work_date === null,
    workDate: r.work_date,
    startTime: r.start_time?.slice(0, 5) ?? null,
    endTime: r.end_time?.slice(0, 5) ?? null,
    startsAt: r.starts_at,
    endsAt: r.ends_at,
  };
}

async function assertNoOverlap(q: TenantQueryable, staffId: string, body: z.infer<typeof CreateBreak>): Promise<void> {
  const existing = await BreaksRepo.listForStaff(q, staffId);
  if (body.startTime && body.endTime) {
    const clashes = existing.some((b) => b.work_date === null && recurringBreaksOverlap(body.startTime!, body.endTime!, b.start_time!, b.end_time!));
    if (clashes) throw Errors.conflict('BREAK_OVERLAP', 'تتعارض هذه الاستراحة مع استراحة أخرى لهذا الحلاق');
  } else {
    const s = new Date(body.startsAt!);
    const e = new Date(body.endsAt!);
    const clashes = existing.some((b) => b.work_date === body.workDate && b.starts_at && b.ends_at && datedBreaksOverlap(s, e, b.starts_at, b.ends_at));
    if (clashes) throw Errors.conflict('BREAK_OVERLAP', 'تتعارض هذه الاستراحة مع استراحة أخرى لهذا الحلاق في نفس اليوم');
  }
}

/** Recurring/dated breaks — rest, prayer, emergency, or "walk-in only" (ق33) — per barber or all. */
@Controller('manager/breaks')
@Roles('manager')
export class BreaksController {
  @Get()
  async list(@Tenant() t: TenantContext) {
    return (await BreaksRepo.list(t.db)).map(toDto);
  }

  @Post()
  async create(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Body(new ZodPipe(CreateBreak)) body: z.infer<typeof CreateBreak>, @Req() req: Request) {
    return t.db.tx(async (q) => {
      const staffIds: string[] =
        body.staffId === 'all' ? (await StaffRepo.list(q)).filter((s) => s.active).map((s) => s.id) : [body.staffId];
      if (staffIds.length === 0) throw Errors.validation([{ path: 'staffId', code: 'not_found' }]);
      if (body.staffId !== 'all') {
        const staff = await StaffRepo.findById(q, body.staffId);
        if (!staff) throw Errors.validation([{ path: 'staffId', code: 'not_found' }]);
      }
      const created: BreakRow[] = [];
      for (const staffId of staffIds) {
        await assertNoOverlap(q, staffId, body);
        const row = body.startTime
          ? await BreaksRepo.insertRecurring(q, staffId, body.type, `${body.startTime}:00`, `${body.endTime}:00`, me.subjectId)
          : await BreaksRepo.insertDated(q, staffId, body.workDate!, body.type, body.startsAt!, body.endsAt!, me.subjectId);
        created.push(row);
      }
      await writeAudit(q, {
        actorKind: 'staff', actorId: me.subjectId, action: 'break.created', targetKind: 'break', ip: clientIp(req),
        details: { staffId: body.staffId, type: body.type, count: created.length },
      });
      return created.map(toDto);
    });
  }

  @Delete(':id')
  @HttpCode(200)
  async remove(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Param('id', new ParseUUIDPipe({ version: '4', exceptionFactory: () => Errors.notFound() })) id: string, @Req() req: Request) {
    return t.db.tx(async (q) => {
      const ok = await BreaksRepo.delete(q, id);
      if (!ok) throw Errors.notFound();
      await writeAudit(q, { actorKind: 'staff', actorId: me.subjectId, action: 'break.removed', targetKind: 'break', targetId: id, ip: clientIp(req) });
      return { ok: true };
    });
  }
}

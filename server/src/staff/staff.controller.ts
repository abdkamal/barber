import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, Put, Req } from '@nestjs/common';
import type { Request } from 'express';
import { z } from 'zod';
import { Roles } from '../auth/auth.decorators';
import { PasswordHasher, passwordPolicyError } from '../auth/passwords';
import { PasswordResetService } from '../auth/password-reset.service';
import type { Principal } from '../auth/principal';
import { SessionsRepo } from '../auth/sessions';
import { Errors } from '../common/errors';
import { normalizeUsername, USERNAME_RE } from '../common/normalize';
import { ZodPipe } from '../common/zod.pipe';
import { isUniqueViolation } from '../db/sql';
import { writeAudit } from '../security/audit';
import { clientIp } from '../security/client-ip';
import { RateLimit } from '../security/rate-limit.guard';
import type { TenantContext } from '../tenancy/tenant-context';
import { CurrentPrincipal, Tenant } from '../tenancy/tenant.decorator';
import { StaffRepo } from './staff.repository';

const CreateStaff = z.object({
  name: z.string().trim().min(1).max(80),
  username: z.string().min(3).max(32),
  password: z.string().min(1).max(128),
  role: z.enum(['barber', 'manager']).default('barber'),
});
const UpdateStaff = z
  .object({
    name: z.string().trim().min(1).max(80).optional(),
    role: z.enum(['barber', 'manager']).optional(),
    active: z.boolean().optional(),
    callAheadMinutes: z.number().int().min(0).max(240).optional(),
  })
  .strict();

const uuid = new ParseUUIDPipe({ version: '4', exceptionFactory: () => Errors.notFound() });

/** Staff management (manager only). */
@Controller('manager/staff')
@Roles('manager')
export class StaffController {
  constructor(
    private readonly hasher: PasswordHasher,
    private readonly resets: PasswordResetService,
  ) {}

  @Get()
  list(@Tenant() t: TenantContext) {
    return StaffRepo.list(t.db);
  }

  @Post()
  async create(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Body(new ZodPipe(CreateStaff)) body: z.infer<typeof CreateStaff>, @Req() req: Request) {
    const username = normalizeUsername(body.username);
    if (!USERNAME_RE.test(username)) throw Errors.validation([{ path: 'username', code: 'invalid_username' }]);
    const min = passwordPolicyError('staff', body.password);
    if (min !== null) throw Errors.weakPassword(min);
    const passwordHash = await this.hasher.hash(body.password);
    try {
      return await t.db.tx(async (q) => {
        const s = await StaffRepo.insert(q, { name: body.name, username, passwordHash, role: body.role });
        await writeAudit(q, {
          actorKind: 'staff', actorId: me.subjectId, action: 'staff.created', targetKind: 'staff', targetId: s.id,
          ip: clientIp(req), details: { role: s.role },
        });
        return s;
      });
    } catch (e) {
      if (isUniqueViolation(e, 'staff_username_key')) throw Errors.usernameTaken();
      throw e;
    }
  }

  @Put(':id')
  async update(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Param('id', uuid) id: string, @Body(new ZodPipe(UpdateStaff)) body: z.infer<typeof UpdateStaff>, @Req() req: Request) {
    return t.db.tx(async (q) => {
      const before = await StaffRepo.findById(q, id);
      if (!before) throw Errors.notFound();
      const roleChanged = body.role !== undefined && body.role !== before.role;
      const deactivated = body.active === false && before.active;
      if (id === me.subjectId && (roleChanged || deactivated)) {
        throw Errors.conflict('CANNOT_CHANGE_OWN_ACCESS', 'لا يمكنك تغيير صلاحياتك أو إيقاف حسابك بنفسك');
      }
      // Review L5: the salon owner cannot be demoted or deactivated by another manager, and the
      // salon always keeps at least one active manager.
      if (before.is_owner && (roleChanged || deactivated)) {
        throw Errors.conflict('OWNER_PROTECTED', 'لا يمكن تغيير صلاحيات مالك الصالون أو إيقاف حسابه');
      }
      const losesManager = before.role === 'manager' && before.active && ((roleChanged && body.role !== 'manager') || deactivated);
      if (losesManager && (await StaffRepo.countActiveManagers(q)) <= 1) {
        throw Errors.conflict('LAST_MANAGER', 'يجب أن يبقى للصالون مدير نشط واحد على الأقل');
      }
      const s = await StaffRepo.update(q, id, body, roleChanged || deactivated);
      if (roleChanged || deactivated) await SessionsRepo.revokeAllFor(q, 'staff', id, roleChanged ? 'role_changed' : 'deactivated');
      if (roleChanged || body.active !== undefined) {
        await writeAudit(q, {
          actorKind: 'staff', actorId: me.subjectId, action: 'staff.access_changed', targetKind: 'staff', targetId: id, ip: clientIp(req),
          details: { from: { role: before.role, active: before.active }, to: { role: s!.role, active: s!.active } },
        });
      }
      return s;
    });
  }

  /** One-time reset code for a barber (managers' own passwords are reset by the vendor). */
  @Post(':id/reset-code')
  @HttpCode(200)
  @RateLimit({ name: 'sensitive' })
  async resetCode(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Param('id', uuid) id: string, @Req() req: Request) {
    const s = await StaffRepo.findById(t.db, id);
    if (!s) throw Errors.notFound();
    if (s.role !== 'barber') throw Errors.forbidden();
    return this.resets.issue(t, { kind: 'staff', id }, { kind: 'staff', staffId: me.subjectId }, clientIp(req));
  }
}

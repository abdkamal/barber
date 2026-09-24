import { Body, Controller, Get, HttpCode, Post, Req } from '@nestjs/common';
import type { Request } from 'express';
import { z } from 'zod';
import { ZodPipe } from '../common/zod.pipe';
import { clientIp } from '../security/client-ip';
import { normalizePhone, normalizeSalonCode, normalizeUsername } from '../common/normalize';
import { RateLimit } from '../security/rate-limit.guard';
import { CurrentPrincipal, Tenant } from '../tenancy/tenant.decorator';
import type { TenantContext } from '../tenancy/tenant-context';
import { Public } from './auth.decorators';
import { AuthService, SessionResponse } from './auth.service';
import { PasswordResetService } from './password-reset.service';
import type { Principal } from './principal';

const salonCode = z.string().min(1).max(16);
const password = z.string().min(1).max(128);

const CustomerRegister = z.object({
  salonCode,
  name: z.string().trim().min(1).max(80),
  phone: z.string().min(1).max(32),
  password,
});
const CustomerLogin = z.object({ salonCode, phone: z.string().min(1).max(32), password });
const StaffLogin = z.object({ salonCode, username: z.string().min(1).max(64), password });
const RefreshBody = z.object({ refreshToken: z.string().min(1).max(4096) });
const ResetBody = z.object({
  salonCode,
  identifier: z.string().min(1).max(64),
  code: z.string().min(1).max(32),
  newPassword: password,
});

/**
 * Per-account rate-limit key, derived AFTER the same normalisation the service applies (review M1):
 * «٠٥٠…», «050-…» and «050 …» are one phone, « RAHA-27 » and «raha-27» one salon, so an attacker
 * cannot multiply his budget by spelling the same account differently.
 */
const acct = (field: 'phone' | 'username' | 'identifier') => (req: Request) => {
  const code = normalizeSalonCode(rawField(req, 'salonCode'));
  const raw = rawField(req, field);
  const id = field === 'phone' ? normalizePhone(raw) : field === 'username' ? normalizeUsername(raw) : normalizePhone(raw) ?? normalizeUsername(raw);
  return code && id ? `${code}|${id}` : undefined;
};

function rawField(req: Request, field: string): string {
  const v = (req.body as Record<string, unknown> | undefined)?.[field];
  return typeof v === 'string' ? v.slice(0, 64) : '';
}

@Controller('auth')
export class AuthController {
  constructor(
    private readonly auth: AuthService,
    private readonly resets: PasswordResetService,
  ) {}

  @Public()
  @Post('customer/register')
  @RateLimit({ name: 'register', account: acct('phone') })
  customerRegister(@Body(new ZodPipe(CustomerRegister)) body: z.infer<typeof CustomerRegister>, @Req() req: Request): Promise<SessionResponse> {
    return this.auth.customerRegister(body, clientIp(req));
  }

  @Public()
  @Post('customer/login')
  @HttpCode(200)
  @RateLimit({ name: 'login', account: acct('phone') })
  customerLogin(@Body(new ZodPipe(CustomerLogin)) body: z.infer<typeof CustomerLogin>, @Req() req: Request): Promise<SessionResponse> {
    return this.auth.customerLogin(body, clientIp(req));
  }

  @Public()
  @Post('staff/login')
  @HttpCode(200)
  @RateLimit({ name: 'login', account: acct('username') })
  staffLogin(@Body(new ZodPipe(StaffLogin)) body: z.infer<typeof StaffLogin>, @Req() req: Request): Promise<SessionResponse> {
    return this.auth.staffLogin(body, clientIp(req));
  }

  @Public()
  @Post('refresh')
  @HttpCode(200)
  @RateLimit({ name: 'refresh' })
  refresh(@Body(new ZodPipe(RefreshBody)) body: z.infer<typeof RefreshBody>, @Req() req: Request): Promise<SessionResponse> {
    return this.auth.refresh(body.refreshToken, clientIp(req));
  }

  @Public()
  @Post('logout')
  @HttpCode(204)
  @RateLimit({ name: 'refresh' })
  async logout(@Body(new ZodPipe(RefreshBody)) body: z.infer<typeof RefreshBody>, @Req() req: Request): Promise<void> {
    await this.auth.logout(body.refreshToken, clientIp(req));
  }

  @Public()
  @Post('reset')
  @HttpCode(204)
  @RateLimit({ name: 'passwordReset', account: acct('identifier') })
  async reset(@Body(new ZodPipe(ResetBody)) body: z.infer<typeof ResetBody>, @Req() req: Request): Promise<void> {
    await this.resets.redeem(body, clientIp(req));
  }

  /** Current session info (lets apps restore state after "auto login"). */
  @Get('session')
  session(@CurrentPrincipal() p: Principal, @Tenant() t: TenantContext) {
    const { code, name, status, timezone, currency } = t.salon;
    return {
      role: p.role,
      accountId: p.subjectId,
      ...(p.customerStatus ? { accountStatus: p.customerStatus } : {}),
      salon: { code, name, status, timezone, currency },
    };
  }
}

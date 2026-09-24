import { Body, Controller, Get, HttpCode, Post, Req } from '@nestjs/common';
import type { Request } from 'express';
import { z } from 'zod';
import { ZodPipe } from '../common/zod.pipe';
import { clientIp } from '../security/client-ip';
import { bodyField, RateLimit } from '../security/rate-limit.guard';
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

const acct = (field: string) => (req: Request) => {
  const code = bodyField(req, 'salonCode');
  const id = bodyField(req, field);
  return code && id ? `${code}|${id}` : undefined;
};

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

import { Body, Controller, Get, Put, Req } from '@nestjs/common';
import type { Request } from 'express';
import { z } from 'zod';
import { Roles } from '../auth/auth.decorators';
import type { Principal } from '../auth/principal';
import { ZodPipe } from '../common/zod.pipe';
import { writeAudit } from '../security/audit';
import { clientIp } from '../security/client-ip';
import type { TenantContext } from '../tenancy/tenant-context';
import { CurrentPrincipal, Tenant } from '../tenancy/tenant.decorator';
import { SettingsRepo, toSettingsDto } from './settings.repository';

const minutes = (max: number) => z.number().int().min(0).max(max);
const UpdateSettings = z
  .object({
    requireAccountApproval: z.boolean(),
    maxActiveBookingsPerCustomer: z.number().int().min(1).max(10),
    bookingOpensBeforeMinutes: minutes(1440),
    etaChangeNotifyMinutes: z.number().int().min(1).max(240),
    maxDisconnectWindowMinutes: minutes(1440),
    gapMarginMinMinutes: minutes(240),
    gapMarginPercent: z.number().int().min(0).max(400),
    offerHoldMinutes: z.number().int().min(1).max(60),
    barberNotConnectedAlertMinutes: minutes(240),
    overrunAlertPercent: z.number().int().min(50).max(500),
    // Round 2 (item 1): how long after its shift end a past day may stay operational (ق24).
    dayCloseGraceMinutes: z.number().int().min(60).max(720),
  })
  .partial()
  .strict();

/** Salon settings (design §11), manager only. */
@Controller('manager/settings')
@Roles('manager')
export class SettingsController {
  @Get()
  async get(@Tenant() t: TenantContext) {
    return toSettingsDto(await SettingsRepo.get(t.db));
  }

  @Put()
  async update(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Body(new ZodPipe(UpdateSettings)) body: z.infer<typeof UpdateSettings>, @Req() req: Request) {
    return t.db.tx(async (q) => {
      const row = await SettingsRepo.update(q, body);
      await writeAudit(q, {
        actorKind: 'staff', actorId: me.subjectId, action: 'settings.updated', targetKind: 'settings', ip: clientIp(req),
        details: { changed: Object.keys(body) },
      });
      return toSettingsDto(row);
    });
  }
}

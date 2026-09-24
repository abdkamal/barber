import { Body, Controller, Delete, Get, Headers, HttpCode, Param, ParseUUIDPipe, Post, Req } from '@nestjs/common';
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
import { BookingService } from './booking.service';

const uuid = z.string().uuid();
const isoTime = z.string().datetime({ offset: true });

const PlaceBody = z
  .object({
    serviceIds: z.array(uuid).min(1).max(10),
    barberId: uuid.optional(),
    kind: z.enum(['queue', 'requested']),
    requestedAt: isoTime.optional(),
  })
  .strict()
  .refine((b) => (b.kind === 'requested') === (b.requestedAt !== undefined), { message: 'requestedAt required only for requested', path: ['requestedAt'] });

const CreateBody = z.union([z.object({ offerId: uuid }).strict(), PlaceBody]);
const SeenBody = z.object({ eta: isoTime }).strict();
const ChangeBody = z
  .object({ kind: z.enum(['queue', 'requested']), requestedAt: isoTime.optional() })
  .strict()
  .refine((b) => (b.kind === 'requested') === (b.requestedAt !== undefined), { message: 'requestedAt required only for requested', path: ['requestedAt'] });

const idParam = new ParseUUIDPipe({ exceptionFactory: () => Errors.notFound() });

/** Customer booking endpoints (api.md "الزبون"). */
@Controller()
@Roles('customer')
export class BookingsController {
  constructor(private readonly bookings: BookingService) {}

  @Get('customer/today')
  today(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal) {
    return this.bookings.today(t, me);
  }

  @Post('bookings/quote')
  @HttpCode(200)
  quote(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Body(new ZodPipe(PlaceBody)) body: z.infer<typeof PlaceBody>, @Headers('idempotency-key') key?: string) {
    return this.bookings.quote(t, me, body, idempotencyKey(key));
  }

  @Post('bookings')
  create(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Body(new ZodPipe(CreateBody)) body: z.infer<typeof CreateBody>, @Headers('idempotency-key') key?: string) {
    return this.bookings.create(t, me, body, idempotencyKey(key));
  }

  @Delete('offers/:id')
  @HttpCode(204)
  async rejectOffer(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Param('id', idParam) id: string) {
    await this.bookings.rejectOffer(t, me, id);
  }

  @Get('bookings/current')
  current(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal) {
    return this.bookings.current(t, me);
  }

  @Post('bookings/:id/seen')
  @HttpCode(204)
  async seen(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Param('id', idParam) id: string, @Body(new ZodPipe(SeenBody)) body: z.infer<typeof SeenBody>) {
    await this.bookings.seen(t, me, id, Date.parse(body.eta));
  }

  @Post('bookings/:id/change-time')
  @HttpCode(200)
  changeTime(
    @Tenant() t: TenantContext,
    @CurrentPrincipal() me: Principal,
    @Param('id', idParam) id: string,
    @Body(new ZodPipe(ChangeBody)) body: z.infer<typeof ChangeBody>,
    @Headers('idempotency-key') key?: string,
  ) {
    return this.bookings.changeTime(t, me, id, body, idempotencyKey(key));
  }

  @Post('bookings/:id/cancel')
  @HttpCode(200)
  cancel(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Param('id', idParam) id: string, @Req() req: Request, @Headers('idempotency-key') key?: string) {
    return this.bookings.cancel(t, me, id, idempotencyKey(key), clientIp(req));
  }

  @Get('customer/history')
  history(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal) {
    return this.bookings.history(t, me);
  }
}

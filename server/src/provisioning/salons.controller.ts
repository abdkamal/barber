import { isOpenNow, publicWeeklyHours, type ScheduleRow } from '../schedules/public-hours';
import { Body, Controller, Get, Param, Post, Req } from '@nestjs/common';
import type { Request } from 'express';
import { z } from 'zod';
import { Public } from '../auth/auth.decorators';
import { AuthService } from '../auth/auth.service';
import { Errors } from '../common/errors';
import { normalizeSalonCode, SALON_CODE_RE } from '../common/normalize';
import { ZodPipe } from '../common/zod.pipe';
import { clientIp } from '../security/client-ip';
import { RateLimit } from '../security/rate-limit.guard';
import { TenantResolver } from '../tenancy/tenant-resolver.service';
import { ProvisioningService } from './provisioning.service';

const RegisterSalon = z.object({
  salon: z.object({
    name: z.string().trim().min(2).max(80),
    timezone: z.string().min(1).max(64),
    currency: z.string().length(3),
    phone: z.string().trim().max(32).optional(),
    address: z.string().trim().max(300).optional(),
    about: z.string().trim().max(2000).optional(),
  }),
  owner: z.object({
    name: z.string().trim().min(1).max(80),
    username: z.string().min(3).max(32),
    password: z.string().min(1).max(128),
  }),
});

@Controller('salons')
export class SalonsController {
  constructor(
    private readonly provisioning: ProvisioningService,
    private readonly resolver: TenantResolver,
    private readonly auth: AuthService,
  ) {}

  /** Salon self-registration (ق37). The salon stays invisible to customers until the vendor activates it. */
  @Public()
  @Post('register')
  @RateLimit({ name: 'salonRegister' })
  async register(@Body(new ZodPipe(RegisterSalon)) body: z.infer<typeof RegisterSalon>, @Req() req: Request) {
    const ip = clientIp(req);
    const rec = await this.provisioning.register(body, ip);
    // The owner can sign in right away to prepare the salon profile while activation is pending.
    const session = await this.auth.staffLogin({ salonCode: rec.code, username: body.owner.username, password: body.owner.password }, ip);
    return {
      salon: { code: rec.code, name: rec.name, status: rec.status, timezone: rec.timezone, currency: rec.currency },
      session,
    };
  }

  /** Public "about the salon" profile — ACTIVE salons only (pending/suspended look like unknown codes). */
  @Public()
  @Get(':code')
  @RateLimit({ name: 'publicLookup' })
  async publicProfile(@Param('code') raw: string) {
    const code = normalizeSalonCode(raw ?? '');
    if (!SALON_CODE_RE.test(code)) throw Errors.salonNotFound();
    const found = await this.resolver.forCode(code);
    if (!found || found.record.status !== 'active') throw Errors.salonNotFound();
    const t = found.tenant;
    const [profile, photos, catalog, services, schedules] = await Promise.all([
      t.db.query(
        `SELECT name, about, logo_path, address, latitude::float8 AS latitude, longitude::float8 AS longitude,
                phone, whatsapp, social_links FROM salon_profile WHERE id = 1`,
      ),
      t.db.query('SELECT id, path, position FROM salon_photos ORDER BY position'),
      t.db.query(
        `SELECT id, kind, name, description, features, price_minor, photo_path, service_id
           FROM catalog_items WHERE visible ORDER BY kind, position, name`,
      ),
      t.db.query('SELECT id, name, base_duration_minutes, price_minor FROM services WHERE active ORDER BY position, name'),
      t.db.query<ScheduleRow>("SELECT staff_id, weekday, to_char(opens_at, 'HH24:MI:SS') AS opens_at, to_char(closes_at, 'HH24:MI:SS') AS closes_at FROM work_schedules"),
    ]);
    const salonCode = found.record.code;
    // Stored paths are `{salonId}/{file}`; the public URL is keyed by salon code (media controller).
    const mediaUrl = (path: string | null | undefined) => (path ? `/v1/media/${salonCode}/${path.split('/').pop()}` : null);
    const p = profile.rows[0] ?? {};
    return {
      code: salonCode,
      name: p.name ?? found.record.name,
      timezone: found.record.timezone,
      currency: found.record.currency,
      about: p.about ?? null,
      logo: mediaUrl(p.logo_path),
      address: p.address ?? null,
      location: p.latitude != null ? { lat: p.latitude, lng: p.longitude } : null,
      contact: { phone: p.phone ?? null, whatsapp: p.whatsapp ?? null, social: p.social_links ?? [] },
      photos: photos.rows.map((r) => ({ id: r.id, url: mediaUrl(r.path), position: r.position })),
      hours: publicWeeklyHours(schedules.rows),
      openNow: isOpenNow(schedules.rows, found.record.timezone),
      services: services.rows.map((r) => ({
        id: r.id,
        name: r.name,
        durationMin: r.base_duration_minutes,
        price: Number(r.price_minor),
      })),
      catalog: catalog.rows.map((r) => ({
        id: r.id,
        kind: r.kind,
        name: r.name,
        description: r.description,
        features: r.features,
        price: r.price_minor == null ? null : Number(r.price_minor),
        photo: mediaUrl(r.photo_path),
        serviceId: r.service_id,
      })),
    };
  }
}

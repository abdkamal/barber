import { Body, Controller, Get, Put, Req } from '@nestjs/common';
import type { Request } from 'express';
import { z } from 'zod';
import { Roles } from '../auth/auth.decorators';
import type { Principal } from '../auth/principal';
import { ZodPipe } from '../common/zod.pipe';
import { normalizePhone } from '../common/normalize';
import { Errors } from '../common/errors';
import { writeAudit } from '../security/audit';
import { clientIp } from '../security/client-ip';
import type { TenantContext } from '../tenancy/tenant-context';
import { CurrentPrincipal, Tenant } from '../tenancy/tenant.decorator';
import { mediaUrl } from '../storage/media-url';
import { PhotosRepo, ProfileRepo, SalonPhotoRow, SalonProfileRow } from './profile.repository';

const SocialLink = z.object({
  platform: z.string().trim().min(1).max(40),
  // Review L3: https links only (no javascript:, data:, http: … on the public salon page).
  url: z
    .string()
    .trim()
    .max(300)
    .url()
    .refine((u) => {
      try {
        const p = new URL(u);
        return p.protocol === 'https:' && !!p.hostname && !p.username && !p.password;
      } catch {
        return false;
      }
    }, { message: 'https_only' }),
});

// All fields optional except `name` (design §2/§10, ق37) — PUT is a partial update: fields left
// out keep their current value, `null` clears an optional one.
const UpdateProfile = z
  .object({
    name: z.string().trim().min(2).max(80).optional(),
    about: z.string().trim().max(2000).nullable().optional(),
    address: z.string().trim().max(300).nullable().optional(),
    location: z.object({ lat: z.number().min(-90).max(90), lng: z.number().min(-180).max(180) }).nullable().optional(),
    phone: z.string().trim().max(32).nullable().optional(),
    whatsapp: z.string().trim().max(32).nullable().optional(),
    socialLinks: z.array(SocialLink).max(10).optional(),
  })
  .strict();

function toDto(t: TenantContext, r: SalonProfileRow, photos: SalonPhotoRow[]) {
  return {
    code: t.salon.code,
    name: r.name,
    about: r.about,
    // Same media URLs as the public profile (GET /v1/media/{code}/{file}; served once the salon is active).
    logo: mediaUrl(t.salon.code, r.logo_path),
    photos: photos.map((p) => ({ id: p.id, url: mediaUrl(t.salon.code, p.path)!, position: p.position })),
    address: r.address,
    location: r.latitude != null ? { lat: r.latitude, lng: r.longitude } : null,
    phone: r.phone,
    whatsapp: r.whatsapp,
    socialLinks: r.social_links,
    updatedAt: r.updated_at,
  };
}

/** Salon profile (design §2/§10, ق37): name, about, address, location, contact, social links. */
@Controller('manager/profile')
@Roles('manager')
export class ProfileController {
  @Get()
  async get(@Tenant() t: TenantContext) {
    return toDto(t, await ProfileRepo.get(t.db), await PhotosRepo.list(t.db));
  }

  @Put()
  async update(
    @Tenant() t: TenantContext,
    @CurrentPrincipal() me: Principal,
    @Body(new ZodPipe(UpdateProfile)) body: z.infer<typeof UpdateProfile>,
    @Req() req: Request,
  ) {
    const patch: Record<string, unknown> = {};
    if (body.name !== undefined) patch.name = body.name;
    if (body.about !== undefined) patch.about = body.about;
    if (body.address !== undefined) patch.address = body.address;
    if (body.location !== undefined) {
      patch.latitude = body.location?.lat ?? null;
      patch.longitude = body.location?.lng ?? null;
    }
    if (body.phone !== undefined) {
      const normalized = body.phone === null ? null : normalizePhone(body.phone);
      if (body.phone !== null && normalized === null) throw Errors.validation([{ path: 'phone', code: 'invalid_phone' }]);
      patch.phone = normalized;
    }
    if (body.whatsapp !== undefined) {
      const normalized = body.whatsapp === null ? null : normalizePhone(body.whatsapp);
      if (body.whatsapp !== null && normalized === null) throw Errors.validation([{ path: 'whatsapp', code: 'invalid_phone' }]);
      patch.whatsapp = normalized;
    }
    if (body.socialLinks !== undefined) patch.socialLinks = body.socialLinks;

    return t.db.tx(async (q) => {
      const row = await ProfileRepo.update(q, patch);
      await writeAudit(q, {
        actorKind: 'staff', actorId: me.subjectId, action: 'profile.updated', targetKind: 'salon_profile', ip: clientIp(req),
        details: { changed: Object.keys(patch) },
      });
      return toDto(t, row, await PhotosRepo.list(q));
    });
  }
}

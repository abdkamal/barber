/// <reference types="multer" />
import { Controller, Delete, HttpCode, Param, ParseUUIDPipe, Post, Req, UploadedFile, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import type { Request } from 'express';
import { Roles } from '../auth/auth.decorators';
import type { Principal } from '../auth/principal';
import { Errors } from '../common/errors';
import { writeAudit } from '../security/audit';
import { clientIp } from '../security/client-ip';
import { ImageStorageService, MAX_UPLOAD_BYTES, splitStoredPath } from '../storage/image-storage.service';
import type { TenantContext } from '../tenancy/tenant-context';
import { CurrentPrincipal, Tenant } from '../tenancy/tenant.decorator';
import { PhotosRepo, ProfileRepo } from './profile.repository';

const uuid = new ParseUUIDPipe({ version: '4', exceptionFactory: () => Errors.notFound() });
const uploadOpts = { limits: { fileSize: MAX_UPLOAD_BYTES } };

/** Salon gallery photos (up to 6, design §2/§7, ق37) and the salon logo. */
@Controller('manager')
@Roles('manager')
export class PhotosController {
  constructor(private readonly storage: ImageStorageService) {}

  @Post('photos')
  @UseInterceptors(FileInterceptor('file', uploadOpts))
  async add(
    @Tenant() t: TenantContext,
    @CurrentPrincipal() me: Principal,
    @UploadedFile() file: Express.Multer.File | undefined,
    @Req() req: Request,
  ) {
    if (!file?.buffer?.length) throw Errors.validation([{ path: 'file', code: 'required' }]);
    return t.db.tx(async (q) => {
      const position = await PhotosRepo.nextFreePosition(q);
      if (position === null) throw Errors.conflict('PHOTOS_LIMIT_REACHED', 'الحد الأقصى 6 صور للصالون');
      const stored = await this.storage.store(t.salonId, file.buffer);
      const row = await PhotosRepo.insert(q, stored.path, position);
      await writeAudit(q, {
        actorKind: 'staff', actorId: me.subjectId, action: 'profile.photo_added', targetKind: 'salon_photo', targetId: row.id,
        ip: clientIp(req),
      });
      return { id: row.id, path: row.path, position: row.position };
    });
  }

  @Delete('photos/:id')
  @HttpCode(200)
  async remove(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Param('id', uuid) id: string, @Req() req: Request) {
    const deleted = await t.db.tx(async (q) => {
      const row = await PhotosRepo.deleteById(q, id);
      if (!row) throw Errors.notFound();
      await writeAudit(q, {
        actorKind: 'staff', actorId: me.subjectId, action: 'profile.photo_removed', targetKind: 'salon_photo', targetId: id, ip: clientIp(req),
      });
      return row;
    });
    const parts = splitStoredPath(deleted.path);
    if (parts) await this.storage.remove(parts.salonId, parts.filename);
    return { ok: true };
  }

  @Post('profile/logo')
  @UseInterceptors(FileInterceptor('file', uploadOpts))
  async setLogo(
    @Tenant() t: TenantContext,
    @CurrentPrincipal() me: Principal,
    @UploadedFile() file: Express.Multer.File | undefined,
    @Req() req: Request,
  ) {
    if (!file?.buffer?.length) throw Errors.validation([{ path: 'file', code: 'required' }]);
    const stored = await this.storage.store(t.salonId, file.buffer, { maxDimensionPx: 800 });
    const old = await t.db.tx(async (q) => {
      const before = await ProfileRepo.get(q);
      await ProfileRepo.setLogo(q, stored.path);
      await writeAudit(q, { actorKind: 'staff', actorId: me.subjectId, action: 'profile.logo_updated', targetKind: 'salon_profile', ip: clientIp(req) });
      return before.logo_path;
    });
    if (old) {
      const parts = splitStoredPath(old);
      if (parts) await this.storage.remove(parts.salonId, parts.filename);
    }
    return { logo: stored.path };
  }

  @Delete('profile/logo')
  @HttpCode(200)
  async removeLogo(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Req() req: Request) {
    const old = await t.db.tx(async (q) => {
      const before = await ProfileRepo.get(q);
      await ProfileRepo.setLogo(q, null);
      await writeAudit(q, { actorKind: 'staff', actorId: me.subjectId, action: 'profile.logo_removed', targetKind: 'salon_profile', ip: clientIp(req) });
      return before.logo_path;
    });
    if (old) {
      const parts = splitStoredPath(old);
      if (parts) await this.storage.remove(parts.salonId, parts.filename);
    }
    return { ok: true };
  }
}

/// <reference types="multer" />
import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Post, Put, Req, UploadedFile, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import type { Request } from 'express';
import { z } from 'zod';
import { Roles } from '../auth/auth.decorators';
import type { Principal } from '../auth/principal';
import { Errors } from '../common/errors';
import { ZodPipe } from '../common/zod.pipe';
import { writeAudit } from '../security/audit';
import { clientIp } from '../security/client-ip';
import { ImageStorageService, MAX_UPLOAD_BYTES, splitStoredPath } from '../storage/image-storage.service';
import type { TenantContext } from '../tenancy/tenant-context';
import { CurrentPrincipal, Tenant } from '../tenancy/tenant.decorator';
import { CatalogItemRow, CatalogRepo } from './catalog.repository';
import { ServicesRepo } from './services.repository';

const CreateCatalogItem = z
  .object({
    kind: z.enum(['service', 'product']),
    name: z.string().trim().min(1).max(80),
    description: z.string().trim().max(2000).nullable().optional(),
    features: z.array(z.string().trim().min(1).max(120)).max(20).default([]),
    price: z.number().int().min(0).nullable().optional(),
    position: z.number().int().min(0).optional(),
    visible: z.boolean().optional(),
    // kind = 'service' only: either link an existing bookable service, or create one inline.
    serviceId: z.string().uuid().optional(),
    durationMinutes: z.number().int().min(1).max(600).optional(),
  })
  .strict()
  .refine((b) => b.kind !== 'service' || b.serviceId || b.durationMinutes, {
    message: 'a service catalog item needs serviceId or durationMinutes to create one',
    path: ['serviceId'],
  });

const UpdateCatalogItem = z
  .object({
    name: z.string().trim().min(1).max(80).optional(),
    description: z.string().trim().max(2000).nullable().optional(),
    features: z.array(z.string().trim().min(1).max(120)).max(20).optional(),
    price: z.number().int().min(0).nullable().optional(),
    position: z.number().int().min(0).optional(),
    visible: z.boolean().optional(),
  })
  .strict();

const uuid = new ParseUUIDPipe({ version: '4', exceptionFactory: () => Errors.notFound() });
const uploadOpts = { limits: { fileSize: MAX_UPLOAD_BYTES } };

function toDto(r: CatalogItemRow) {
  return {
    id: r.id,
    kind: r.kind,
    name: r.name,
    description: r.description,
    features: r.features,
    price: r.price_minor == null ? null : Number(r.price_minor),
    photo: r.photo_path,
    position: r.position,
    visible: r.visible,
    serviceId: r.service_id,
  };
}

/**
 * The salon's catalog (ق37): visible services & products with price/description/features/photo.
 * A "service" item links to a bookable `services` row — created together and kept in sync.
 */
@Controller('manager/catalog')
@Roles('manager')
export class CatalogController {
  constructor(private readonly storage: ImageStorageService) {}

  @Get()
  async list(@Tenant() t: TenantContext) {
    return (await CatalogRepo.list(t.db)).map(toDto);
  }

  @Post()
  async create(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Body(new ZodPipe(CreateCatalogItem)) body: z.infer<typeof CreateCatalogItem>, @Req() req: Request) {
    return t.db.tx(async (q) => {
      let serviceId: string | null = null;
      if (body.kind === 'service') {
        if (body.serviceId) {
          const svc = await ServicesRepo.findById(q, body.serviceId);
          if (!svc) throw Errors.validation([{ path: 'serviceId', code: 'not_found' }]);
          serviceId = svc.id;
        } else {
          const svc = await ServicesRepo.insert(q, { name: body.name, durationMinutes: body.durationMinutes!, priceMinor: body.price ?? 0 });
          serviceId = svc.id;
        }
      }
      const item = await CatalogRepo.insert(q, {
        kind: body.kind,
        name: body.name,
        description: body.description ?? null,
        features: body.features,
        priceMinor: body.price ?? null,
        position: body.position ?? 0,
        visible: body.visible ?? true,
        serviceId,
      });
      await writeAudit(q, { actorKind: 'staff', actorId: me.subjectId, action: 'catalog.created', targetKind: 'catalog_item', targetId: item.id, ip: clientIp(req) });
      return toDto(item);
    });
  }

  @Put(':id')
  async update(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Param('id', uuid) id: string, @Body(new ZodPipe(UpdateCatalogItem)) body: z.infer<typeof UpdateCatalogItem>, @Req() req: Request) {
    return t.db.tx(async (q) => {
      const before = await CatalogRepo.findById(q, id);
      if (!before) throw Errors.notFound();
      const item = await CatalogRepo.update(q, id, {
        name: body.name,
        description: body.description,
        features: body.features,
        priceMinor: body.price,
        position: body.position,
        visible: body.visible,
      });
      // Keep the linked bookable service's name/price in sync (design: "create/update both consistently").
      if (before.service_id && (body.name !== undefined || body.price !== undefined)) {
        await ServicesRepo.update(q, before.service_id, { name: body.name, priceMinor: body.price ?? undefined });
      }
      await writeAudit(q, { actorKind: 'staff', actorId: me.subjectId, action: 'catalog.updated', targetKind: 'catalog_item', targetId: id, ip: clientIp(req), details: { changed: Object.keys(body) } });
      return toDto(item!);
    });
  }

  @Delete(':id')
  @HttpCode(200)
  async remove(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Param('id', uuid) id: string, @Req() req: Request) {
    const deleted = await t.db.tx(async (q) => {
      const row = await CatalogRepo.delete(q, id);
      if (!row) throw Errors.notFound();
      await writeAudit(q, { actorKind: 'staff', actorId: me.subjectId, action: 'catalog.deleted', targetKind: 'catalog_item', targetId: id, ip: clientIp(req) });
      return row;
      // Note: the underlying bookable `services` row (if any) is kept — it is managed separately
      // via /manager/services and may have booking history.
    });
    if (deleted.photo_path) {
      const parts = splitStoredPath(deleted.photo_path);
      if (parts) await this.storage.remove(parts.salonId, parts.filename);
    }
    return { ok: true };
  }

  @Post(':id/photo')
  @UseInterceptors(FileInterceptor('file', uploadOpts))
  async setPhoto(
    @Tenant() t: TenantContext,
    @CurrentPrincipal() me: Principal,
    @Param('id', uuid) id: string,
    @UploadedFile() file: Express.Multer.File | undefined,
    @Req() req: Request,
  ) {
    if (!file?.buffer?.length) throw Errors.validation([{ path: 'file', code: 'required' }]);
    const before = await CatalogRepo.findById(t.db, id);
    if (!before) throw Errors.notFound();
    const stored = await this.storage.store(t.salonId, file.buffer);
    await t.db.tx(async (q) => {
      await CatalogRepo.update(q, id, { photoPath: stored.path });
      await writeAudit(q, { actorKind: 'staff', actorId: me.subjectId, action: 'catalog.photo_updated', targetKind: 'catalog_item', targetId: id, ip: clientIp(req) });
    });
    if (before.photo_path) {
      const parts = splitStoredPath(before.photo_path);
      if (parts) await this.storage.remove(parts.salonId, parts.filename);
    }
    return { photo: stored.path };
  }

  @Delete(':id/photo')
  @HttpCode(200)
  async removePhoto(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Param('id', uuid) id: string, @Req() req: Request) {
    const before = await CatalogRepo.findById(t.db, id);
    if (!before) throw Errors.notFound();
    await t.db.tx(async (q) => {
      await CatalogRepo.update(q, id, { photoPath: null });
      await writeAudit(q, { actorKind: 'staff', actorId: me.subjectId, action: 'catalog.photo_removed', targetKind: 'catalog_item', targetId: id, ip: clientIp(req) });
    });
    if (before.photo_path) {
      const parts = splitStoredPath(before.photo_path);
      if (parts) await this.storage.remove(parts.salonId, parts.filename);
    }
    return { ok: true };
  }
}

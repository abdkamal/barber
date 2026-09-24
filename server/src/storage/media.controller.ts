import { Controller, Get, Header, Param, StreamableFile } from '@nestjs/common';
import { Public } from '../auth/auth.decorators';
import { Errors } from '../common/errors';
import { normalizeSalonCode, SALON_CODE_RE } from '../common/normalize';
import { RateLimit } from '../security/rate-limit.guard';
import { TenantResolver } from '../tenancy/tenant-resolver.service';
import { FILENAME_RE, ImageStorageService } from './image-storage.service';

/**
 * Serves stored images (salon photos/logo, catalog item photos). Public, but only for ACTIVE
 * salons — an unknown/pending/suspended code looks like a 404, same as the public profile route.
 * Path-traversal safe: both the code and the file name are validated before touching the disk.
 */
@Controller('media')
export class MediaController {
  constructor(
    private readonly resolver: TenantResolver,
    private readonly storage: ImageStorageService,
  ) {}

  @Public()
  @Get(':code/:file')
  @RateLimit({ name: 'publicLookup' })
  @Header('Cache-Control', 'public, max-age=86400, immutable')
  async get(@Param('code') rawCode: string, @Param('file') file: string): Promise<StreamableFile> {
    const code = normalizeSalonCode(rawCode ?? '');
    if (!SALON_CODE_RE.test(code) || !FILENAME_RE.test(file)) throw Errors.notFound();
    const found = await this.resolver.forCode(code);
    if (!found || found.record.status !== 'active') throw Errors.notFound();
    const img = await this.storage.read(found.record.id, file);
    if (!img) throw Errors.notFound();
    return new StreamableFile(img.data, { type: img.contentType });
  }
}

import { randomBytes } from 'node:crypto';
import { mkdir, readFile, stat, unlink, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { Injectable } from '@nestjs/common';
import sharp from 'sharp';
import { Errors } from '../common/errors';

export type ImageKind = 'jpeg' | 'png' | 'webp';

/** Max size accepted for an *uploaded* file, before re-encoding (design §7). */
export const MAX_UPLOAD_BYTES = 5 * 1024 * 1024;

/** The public dimension cap for a photo/logo after resizing. */
const MAX_DIMENSION_PX = 1600;

const EXT_BY_KIND: Record<ImageKind, string> = { jpeg: 'jpg', png: 'png', webp: 'webp' };
export const CONTENT_TYPE_BY_EXT: Record<string, string> = {
  jpg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
};

/** Salon ids are UUIDs; stored filenames are a random 32-hex-char name plus a fixed extension. */
const SALON_ID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const FILENAME_RE = /^[a-f0-9]{32}\.(jpg|png|webp)$/;

/**
 * Sniffs the *actual* file content (magic bytes) — never trust a client-supplied extension or
 * Content-Type. Returns null for anything else, including SVG (rejected — design §7).
 */
export function sniffImageKind(buf: Buffer): ImageKind | null {
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'jpeg';
  if (
    buf.length >= 8 &&
    buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47 &&
    buf[4] === 0x0d && buf[5] === 0x0a && buf[6] === 0x1a && buf[7] === 0x0a
  ) {
    return 'png';
  }
  if (buf.length >= 12 && buf.toString('ascii', 0, 4) === 'RIFF' && buf.toString('ascii', 8, 12) === 'WEBP') return 'webp';
  return null;
}

function storageRoot(): string {
  return resolve(process.cwd(), process.env.STORAGE_DIR?.trim() || './storage-data');
}

/** Validates a stored relative path (`{salonId}/{file}`) and returns its absolute, safe location. */
function safeAbsolutePath(salonId: string, filename: string): string | null {
  if (!SALON_ID_RE.test(salonId) || !FILENAME_RE.test(filename)) return null;
  const root = storageRoot();
  const abs = join(root, salonId, filename);
  // Defence in depth: the regexes above already forbid traversal, but double-check the resolved
  // path never escapes the salon's own directory before touching the filesystem.
  if (!abs.startsWith(join(root, salonId) + '/') && abs !== join(root, salonId, filename)) return null;
  return abs;
}

/**
 * Review H3: image processing (sharp/libvips) is exposed only to salons the vendor has activated —
 * a self-registered, not yet reviewed salon cannot upload files.
 */
export function assertUploadsAllowed(salon: { status: string }): void {
  if (salon.status !== 'active') {
    throw Errors.conflict('SALON_NOT_ACTIVE', 'رفع الصور متاح بعد تفعيل الصالون');
  }
}

export interface StoredImage {
  /** `{salonId}/{randomName}.{ext}` — what gets saved as e.g. salon_photos.path / logo_path. */
  path: string;
  filename: string;
  contentType: string;
}

/**
 * Validates, re-encodes (stripping EXIF/GPS and any other metadata), resizes and stores an
 * uploaded image on local disk, partitioned by salon id with a random file name (design §7).
 */
@Injectable()
export class ImageStorageService {
  async store(salonId: string, buffer: Buffer, opts: { maxDimensionPx?: number } = {}): Promise<StoredImage> {
    if (!buffer || buffer.length === 0) throw Errors.validation([{ path: 'file', code: 'empty' }]);
    if (buffer.length > MAX_UPLOAD_BYTES) throw Errors.validation([{ path: 'file', code: 'too_large' }]);
    const kind = sniffImageKind(buffer);
    if (!kind) throw Errors.validation([{ path: 'file', code: 'unsupported_image_type' }]);

    const maxDim = opts.maxDimensionPx ?? MAX_DIMENSION_PX;
    let pipeline = sharp(buffer, { failOn: 'error' }).rotate(); // auto-orient using EXIF orientation before we drop it
    pipeline = pipeline.resize({ width: maxDim, height: maxDim, fit: 'inside', withoutEnlargement: true });
    // No .withMetadata() call: sharp does NOT copy EXIF/ICC/GPS to the output by default, so
    // re-encoding here also strips location and camera metadata (design §7).
    let out: Buffer;
    switch (kind) {
      case 'jpeg':
        out = await pipeline.jpeg({ quality: 82, mozjpeg: true }).toBuffer();
        break;
      case 'png':
        out = await pipeline.png({ compressionLevel: 8 }).toBuffer();
        break;
      case 'webp':
        out = await pipeline.webp({ quality: 82 }).toBuffer();
        break;
    }
    const ext = EXT_BY_KIND[kind];
    const filename = `${randomBytes(16).toString('hex')}.${ext}`;
    const dir = join(storageRoot(), salonId);
    await mkdir(dir, { recursive: true });
    await writeFile(join(dir, filename), out, { mode: 0o640 });
    return { path: `${salonId}/${filename}`, filename, contentType: CONTENT_TYPE_BY_EXT[ext]! };
  }

  /** Best-effort delete; a missing file is not an error (already gone, or never existed). */
  async remove(salonId: string, filename: string): Promise<void> {
    const abs = safeAbsolutePath(salonId, filename);
    if (!abs) return;
    await unlink(abs).catch(() => undefined);
  }

  /** Reads a stored file for serving. Returns null if the path is unsafe or the file is missing. */
  async read(salonId: string, filename: string): Promise<{ data: Buffer; contentType: string } | null> {
    const abs = safeAbsolutePath(salonId, filename);
    if (!abs) return null;
    try {
      const st = await stat(abs);
      if (!st.isFile()) return null;
      const ext = filename.slice(filename.lastIndexOf('.') + 1);
      return { data: await readFile(abs), contentType: CONTENT_TYPE_BY_EXT[ext] ?? 'application/octet-stream' };
    } catch {
      return null;
    }
  }
}

/** Splits a stored `path` column value (`{salonId}/{file}`) back into its parts, or null if malformed. */
export function splitStoredPath(path: string): { salonId: string; filename: string } | null {
  const i = path.indexOf('/');
  if (i < 0) return null;
  const salonId = path.slice(0, i);
  const filename = path.slice(i + 1);
  if (!SALON_ID_RE.test(salonId) || !FILENAME_RE.test(filename)) return null;
  return { salonId, filename };
}

export { FILENAME_RE };

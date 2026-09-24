/**
 * Public URL of a stored image. Stored paths are `{salonId}/{file}`; the public URL is keyed by
 * salon code (`GET /v1/media/{code}/{file}`, served for active salons only).
 */
export function mediaUrl(salonCode: string, path: string | null | undefined): string | null {
  return path ? `/v1/media/${salonCode}/${path.split('/').pop()}` : null;
}

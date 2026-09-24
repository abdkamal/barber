import type { Request } from 'express';

/** Client IP as resolved by Express (honours TRUST_PROXY; X-Forwarded-For is ignored otherwise). */
export function clientIp(req: Request): string {
  return (req.ip ?? req.socket?.remoteAddress ?? 'unknown').replace(/^::ffff:/, '');
}

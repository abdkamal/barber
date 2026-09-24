import { randomUUID } from 'node:crypto';
import type { NextFunction, Request, Response } from 'express';

/** Header carrying the request id in both directions (a proxy may set it; we echo or generate it). */
export const REQUEST_ID_HEADER = 'X-Request-Id';

/** Accepted incoming ids: short, printable, no spaces (never trust arbitrary client text in logs). */
const INCOMING_RE = /^[A-Za-z0-9._:-]{8,64}$/;

export function requestIdOf(req: Request): string | undefined {
  return (req as Request & { requestId?: string }).requestId;
}

/**
 * Phase 11 trial feedback: every request carries an id — the incoming `X-Request-Id` (from a proxy)
 * when it is well-formed, otherwise a fresh UUID — echoed in the response header so that a user can
 * report the code the app shows and we can find the matching server log line.
 */
export function requestIdMiddleware(req: Request, res: Response, next: NextFunction): void {
  const incoming = req.header(REQUEST_ID_HEADER);
  const id = incoming && INCOMING_RE.test(incoming) ? incoming : randomUUID();
  (req as Request & { requestId?: string }).requestId = id;
  res.setHeader(REQUEST_ID_HEADER, id);
  next();
}

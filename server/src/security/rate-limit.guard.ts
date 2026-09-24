import { CanActivate, ExecutionContext, Inject, Injectable, SetMetadata } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request } from 'express';
import { APP_CONFIG, AppConfig, RateLimitRule } from '../config/config';
import { Errors } from '../common/errors';
import { clientIp } from './client-ip';
import { RateLimiter } from './rate-limiter';

type Rules = { ip: RateLimitRule; account?: RateLimitRule };
export type RateLimitName = Exclude<keyof AppConfig['rateLimits'], 'enabled' | 'global'>;

export interface RateLimitSpec {
  name: RateLimitName;
  /** Derives the per-account key from the (not yet validated) request. */
  account?: (req: Request) => string | undefined;
}

const RATE_LIMIT_KEY = 'saloni:rate-limit';
export const RateLimit = (spec: RateLimitSpec) => SetMetadata(RATE_LIMIT_KEY, spec);

/** Reads a string field of the raw body defensively (guards run before validation pipes). */
export function bodyField(req: Request, field: string): string {
  const v = (req.body as Record<string, unknown> | undefined)?.[field];
  return typeof v === 'string' ? v.trim().toLowerCase().slice(0, 64) : '';
}

/** Per-IP (always) and per-account (where declared) request limits. Responds 429 + Retry-After. */
@Injectable()
export class RateLimitGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly limiter: RateLimiter,
    @Inject(APP_CONFIG) private readonly config: AppConfig,
  ) {}

  canActivate(ctx: ExecutionContext): boolean {
    if (!this.config.rateLimits.enabled) return true;
    const req = ctx.switchToHttp().getRequest<Request>();
    const ip = clientIp(req);
    const spec = this.reflector.getAllAndOverride<RateLimitSpec | undefined>(RATE_LIMIT_KEY, [ctx.getHandler(), ctx.getClass()]);

    let wait = this.limiter.hit(`global|${ip}`, this.config.rateLimits.global);
    if (spec) {
      const rules = this.config.rateLimits[spec.name] as Rules;
      wait = Math.max(wait, this.limiter.hit(`${spec.name}|ip|${ip}`, rules.ip));
      const acct = spec.account?.(req);
      if (rules.account && acct) wait = Math.max(wait, this.limiter.hit(`${spec.name}|acct|${acct}`, rules.account));
    }
    if (wait > 0) throw Errors.tooManyRequests(wait);
    return true;
  }
}

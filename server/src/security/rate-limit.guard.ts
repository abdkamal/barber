import { CanActivate, ExecutionContext, Inject, Injectable, SetMetadata } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request } from 'express';
import { backoffDelayMs } from '../auth/backoff';
import { AccountRules, APP_CONFIG, AppConfig, RateLimitRule } from '../config/config';
import { Errors } from '../common/errors';
import { clientIp } from './client-ip';
import { RateLimiter } from './rate-limiter';

type Rules = { ip: RateLimitRule } & Partial<Omit<AccountRules, 'ip'>>;
export type RateLimitName = Exclude<keyof AppConfig['rateLimits'], 'enabled' | 'global' | 'sync'>;

export interface RateLimitSpec {
  name: RateLimitName;
  /** Derives the per-account key from the (not yet validated) request. */
  account?: (req: Request) => string | undefined;
}

const RATE_LIMIT_KEY = 'saloni:rate-limit';
export const RateLimit = (spec: RateLimitSpec) => SetMetadata(RATE_LIMIT_KEY, spec);

/**
 * Per-IP (always) and per-account+IP (where declared) request limits — 429 + Retry-After.
 * Round 2 (item 6, review M1): the account-wide rule (one account from every address) never
 * refuses: beyond its budget each request is only delayed, progressively, capped at a few seconds
 * (`backoff.accountMaxDelayMs`). An attacker hammering an account from many addresses slows it a
 * little but can never lock the real user out.
 */
@Injectable()
export class RateLimitGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly limiter: RateLimiter,
    @Inject(APP_CONFIG) private readonly config: AppConfig,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    if (!this.config.rateLimits.enabled) return true;
    const req = ctx.switchToHttp().getRequest<Request>();
    const ip = clientIp(req);
    const spec = this.reflector.getAllAndOverride<RateLimitSpec | undefined>(RATE_LIMIT_KEY, [ctx.getHandler(), ctx.getClass()]);

    let wait = this.limiter.hit(`global|${ip}`, this.config.rateLimits.global);
    let delayMs = 0;
    if (spec) {
      const rules = this.config.rateLimits[spec.name] as Rules;
      wait = Math.max(wait, this.limiter.hit(`${spec.name}|ip|${ip}`, rules.ip));
      const acct = spec.account?.(req);
      if (acct && rules.accountIp) wait = Math.max(wait, this.limiter.hit(`${spec.name}|acctip|${acct}|${ip}`, rules.accountIp));
      if (acct && rules.account && wait === 0) {
        const n = this.limiter.count(`${spec.name}|acct|${acct}`, rules.account);
        delayMs = this.accountDelayMs(n, rules.account.limit);
      }
    }
    if (wait > 0) throw Errors.tooManyRequests(wait);
    if (delayMs > 0) await new Promise((r) => setTimeout(r, delayMs));
    return true;
  }

  /** Delay for the n-th request of one account in the window: 0 within the budget, then doubling, capped. */
  accountDelayMs(n: number, free: number): number {
    const b = this.config.backoff;
    return backoffDelayMs(n, { free, baseMs: b.accountBaseMs, maxMs: b.accountMaxDelayMs });
  }
}

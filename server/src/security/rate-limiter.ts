import type { RateLimitRule } from '../config/config';

/**
 * In-memory fixed-window counters. The design runs a single server instance (ق8), so process memory
 * is sufficient; swap for Redis if the server is ever scaled out.
 */
export class RateLimiter {
  private readonly buckets = new Map<string, { count: number; resetAt: number }>();
  private lastSweep = 0;

  constructor(private readonly now: () => number = Date.now) {}

  /** Counts one hit; returns 0 when allowed, otherwise the seconds until the window resets. */
  hit(key: string, rule: RateLimitRule): number {
    const now = this.now();
    this.sweep(now);
    let b = this.buckets.get(key);
    if (!b || b.resetAt <= now) {
      b = { count: 0, resetAt: now + rule.windowMs };
      this.buckets.set(key, b);
    }
    b.count++;
    if (b.count > rule.limit) return Math.max(1, Math.ceil((b.resetAt - now) / 1000));
    return 0;
  }

  /** Counts one hit and returns the number of hits in the current window (never refuses). */
  count(key: string, rule: RateLimitRule): number {
    const now = this.now();
    this.sweep(now);
    let b = this.buckets.get(key);
    if (!b || b.resetAt <= now) {
      b = { count: 0, resetAt: now + rule.windowMs };
      this.buckets.set(key, b);
    }
    return ++b.count;
  }

  reset(): void {
    this.buckets.clear();
  }

  private sweep(now: number): void {
    if (now - this.lastSweep < 60_000 && this.buckets.size < 100_000) return;
    this.lastSweep = now;
    for (const [k, b] of this.buckets) if (b.resetAt <= now) this.buckets.delete(k);
  }
}

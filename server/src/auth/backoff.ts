/**
 * Progressive (exponential) backoff instead of a hard lockout (ق31):
 * the first `free` failures cost nothing, then each further failure doubles the wait, capped at `max`.
 */
export function backoffDelayMs(failures: number, opts: { free: number; baseMs: number; maxMs: number }): number {
  if (failures <= opts.free) return 0;
  const exp = failures - opts.free - 1;
  if (exp >= 40) return opts.maxMs;
  return Math.min(opts.maxMs, opts.baseMs * 2 ** exp);
}

import { DEFAULT_SIM, simulate, type SimConfig } from './simulate.js';
import { MINUTE } from '../types.js';

// Usage: npm run simulate -- [--seeds 20] [--barbers 3] [--demand 7] [--lead 20] [--sigma 0.2]
const args = new Map<string, string>();
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i += 2) args.set(argv[i]!.replace(/^--/, ''), argv[i + 1] ?? '');
const num = (k: string, d: number) => (args.has(k) ? Number(args.get(k)) : d);

const seeds = num('seeds', 20);
const base: SimConfig = {
  ...DEFAULT_SIM,
  barbers: num('barbers', DEFAULT_SIM.barbers),
  demandPerHour: num('demand', DEFAULT_SIM.demandPerHour),
  leadTime: num('lead', 20) * MINUTE,
  durationSigma: num('sigma', DEFAULT_SIM.durationSigma),
};

const runs = Array.from({ length: seeds }, (_, i) => simulate({ ...base, seed: i + 1 }));
const avg = (k: keyof (typeof runs)[number]) => Math.round((runs.reduce((a, r) => a + (r[k] as number), 0) / runs.length) * 100) / 100;
console.log(`Simulated ${seeds} days · ${base.barbers} barbers · ${base.demandPerHour} requests/hour · lead ${base.leadTime / MINUTE} min · sigma ${base.durationSigma}`);
for (const k of ['requests', 'accepted', 'refused', 'served', 'cancelled', 'noShows', 'meanEtaErrorMin', 'p90EtaErrorMin', 'notifiedShare', 'utilization'] as const) {
  console.log(`  ${k.padEnd(16)} ${avg(k)}`);
}

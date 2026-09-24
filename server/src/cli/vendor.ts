/**
 * Vendor (system provider) CLI.
 *   npm run vendor -- list [--status pending_activation|active|suspended]
 *   npm run vendor -- pending
 *   npm run vendor -- activate <CODE>
 *   npm run vendor -- suspend <CODE>
 *   npm run vendor -- reset-manager-password <CODE> [--username <name>]
 */
import { loadConfig, loadDotEnv } from '../config/config';
import { PoolManager } from '../db/pools';
import type { SalonRecord, SalonStatus } from '../directory/directory.repository';
import { VendorError, VendorService } from '../provisioning/vendor.service';

const USAGE = `usage:
  vendor list [--status pending_activation|active|suspended]
  vendor pending
  vendor activate <CODE>
  vendor suspend <CODE>
  vendor reset-manager-password <CODE> [--username <name>]`;

function flag(args: string[], name: string): string | undefined {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
}

function printSalons(rows: SalonRecord[]): void {
  if (!rows.length) return console.log('(none)');
  for (const s of rows) {
    console.log(
      [s.code.padEnd(10), s.status.padEnd(19), `v${s.schema_version}`.padEnd(4), s.registered_at.toISOString(), s.timezone, s.currency, s.name].join('  '),
    );
  }
}

export async function runVendor(args: string[], vendor: VendorService): Promise<number> {
  const [cmd, arg] = args;
  switch (cmd) {
    case 'list': {
      const st = flag(args, '--status') as SalonStatus | undefined;
      printSalons(await vendor.list(st));
      return 0;
    }
    case 'pending':
      printSalons(await vendor.list('pending_activation'));
      return 0;
    case 'activate':
    case 'suspend': {
      if (!arg) break;
      const s = cmd === 'activate' ? await vendor.activate(arg) : await vendor.suspend(arg);
      console.log(`${s.code}: ${s.status}`);
      return 0;
    }
    case 'reset-manager-password': {
      if (!arg) break;
      const r = await vendor.resetManagerPassword(arg, flag(args, '--username'));
      console.log(`One-time reset code for ${r.username} @ ${r.salon}: ${r.code}`);
      console.log(`Valid until ${r.expiresAt.toISOString()}. Give it to the manager over a trusted channel;`);
      console.log('they must choose a new password with it (POST /v1/auth/reset). All their sessions are revoked on use.');
      return 0;
    }
  }
  console.error(USAGE);
  return 2;
}

if (require.main === module) {
  loadDotEnv();
  const config = loadConfig();
  const pools = new PoolManager(config);
  runVendor(process.argv.slice(2), new VendorService(config, pools))
    .catch((e) => {
      console.error(e instanceof VendorError ? e.message : `error: ${(e as Error).message}`);
      return 1;
    })
    .then(async (code) => {
      await pools.close();
      process.exit(code);
    });
}

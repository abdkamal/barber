import { bootLogger, createApp } from './bootstrap';
import { loadConfig, loadDotEnv } from './config/config';

async function main(): Promise<void> {
  loadDotEnv();
  const config = loadConfig();
  const app = await createApp(config);
  await app.listen(config.port, config.host);
  bootLogger.log(`Saloni server listening on ${config.host}:${config.port} (${config.env})`);
}

main().catch((e) => {
  // eslint-disable-next-line no-console
  console.error('Fatal startup error:', (e as Error).message);
  process.exit(1);
});

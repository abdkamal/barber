import 'reflect-metadata';
import { DynamicModule, Module } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import helmet from 'helmet';
import { AppModule } from '../src/app.module';
import { AllExceptionsFilter } from '../src/common/http-exception.filter';
import type { AppConfig } from '../src/config/config';
import { ManagerFeaturesModule } from '../src/profile/manager-features.module';

/**
 * This milestone's controllers (profile/catalog/schedules/reports/storage) are not yet wired into
 * `AppModule` — that file belongs to a concurrently-developed milestone (bookings/sync). Rather than
 * edit it, integration tests boot AppModule *plus* ManagerFeaturesModule side by side, exactly the
 * way the orchestrator will once it adds the one import line from the final report. Everything else
 * (guards, helmet, body parser, exception filter) mirrors `src/bootstrap.ts`.
 */
@Module({})
class TestRootModule {
  static forRoot(config: AppConfig): DynamicModule {
    return { module: TestRootModule, imports: [AppModule.forRoot(config), ManagerFeaturesModule] };
  }
}

export async function createManagerTestApp(config: AppConfig) {
  const app = await NestFactory.create<NestExpressApplication>(TestRootModule.forRoot(config), {
    bodyParser: false,
    logger: false,
  });
  app.set('trust proxy', config.http.trustProxy);
  app.disable('x-powered-by');
  app.useBodyParser('json', { limit: '100kb' });
  app.use(helmet());
  app.setGlobalPrefix('v1');
  app.useGlobalFilters(new AllExceptionsFilter());
  app.enableShutdownHooks();
  return app;
}

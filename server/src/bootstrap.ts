import 'reflect-metadata';
import { INestApplication, Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import helmet from 'helmet';
import { AppModule } from './app.module';
import { AllExceptionsFilter } from './common/http-exception.filter';
import { REQUEST_ID_HEADER, requestIdMiddleware } from './common/request-id';
import type { AppConfig } from './config/config';

/** Builds the HTTP application (shared by main.ts and the integration tests). */
export async function createApp(config: AppConfig, opts: { logger?: false } = {}): Promise<INestApplication> {
  const app = await NestFactory.create<NestExpressApplication>(AppModule.forRoot(config), {
    bodyParser: false,
    logger: opts.logger === false ? false : ['error', 'warn', 'log'],
  });
  app.set('trust proxy', config.http.trustProxy);
  app.disable('x-powered-by');
  // Before the body parser: its errors (malformed JSON, too large) carry the request id too.
  app.use(requestIdMiddleware);
  app.useBodyParser('json', { limit: '100kb' });
  app.use(helmet());
  if (config.http.corsOrigins.length) {
    app.enableCors({
      origin: config.http.corsOrigins,
      methods: ['GET', 'POST', 'PUT', 'DELETE'],
      allowedHeaders: ['Authorization', 'Content-Type', 'Idempotency-Key', REQUEST_ID_HEADER],
      exposedHeaders: [REQUEST_ID_HEADER, 'Retry-After'],
      maxAge: 600,
    });
  }
  app.setGlobalPrefix('v1');
  app.useGlobalFilters(new AllExceptionsFilter());
  app.enableShutdownHooks();
  return app;
}

export const bootLogger = new Logger('Bootstrap');

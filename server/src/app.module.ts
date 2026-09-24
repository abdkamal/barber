import { DynamicModule, Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { AuthGuard } from './auth/auth.guard';
import { AuthModule } from './auth/auth.module';
import { APP_CONFIG, AppConfig } from './config/config';
import { CustomersController } from './customers/customers.controller';
import { DatabaseModule } from './db/database.module';
import { HealthController } from './health/health.controller';
import { QueueModule } from './queue.module';
import { ProvisioningService } from './provisioning/provisioning.service';
import { SalonsController } from './provisioning/salons.controller';
import { RateLimitGuard } from './security/rate-limit.guard';
import { RateLimiter } from './security/rate-limiter';
import { SettingsController } from './settings/settings.controller';
import { StaffController } from './staff/staff.controller';

/**
 * Module seams for later milestones: bookings/queues, sync (events + change feed + WebSocket),
 * timers, notifications (FCM), reports and profile/catalog management plug in here, each using
 * the TenantContext from the verified token. Scheduling logic lives in packages/engine.
 */
@Module({})
export class ConfigModule {
  static forRoot(config: AppConfig): DynamicModule {
    return { module: ConfigModule, global: true, providers: [{ provide: APP_CONFIG, useValue: config }], exports: [APP_CONFIG] };
  }
}

@Module({})
export class AppModule {
  static forRoot(config: AppConfig): DynamicModule {
    return {
      module: AppModule,
      imports: [ConfigModule.forRoot(config), DatabaseModule, AuthModule, QueueModule],
      controllers: [HealthController, SalonsController, StaffController, CustomersController, SettingsController],
      providers: [
        ProvisioningService,
        { provide: RateLimiter, useValue: new RateLimiter() },
        // Order matters: rate limiting runs before authentication.
        { provide: APP_GUARD, useClass: RateLimitGuard },
        { provide: APP_GUARD, useClass: AuthGuard },
      ],
    };
  }
}

import { Global, Inject, Module, OnApplicationShutdown } from '@nestjs/common';
import { APP_CONFIG, AppConfig } from '../config/config';
import { TenantResolver } from '../tenancy/tenant-resolver.service';
import { PoolManager } from './pools';

@Global()
@Module({
  providers: [
    { provide: PoolManager, inject: [APP_CONFIG], useFactory: (c: AppConfig) => new PoolManager(c) },
    TenantResolver,
  ],
  exports: [PoolManager, TenantResolver],
})
export class DatabaseModule implements OnApplicationShutdown {
  constructor(@Inject(PoolManager) private readonly pools: PoolManager) {}

  async onApplicationShutdown(): Promise<void> {
    await this.pools.close();
  }
}

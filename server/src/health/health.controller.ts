import { Controller, Get } from '@nestjs/common';
import { Public } from '../auth/auth.decorators';
import { PoolManager } from '../db/pools';

@Controller('health')
export class HealthController {
  constructor(private readonly pools: PoolManager) {}

  @Public()
  @Get()
  async health() {
    await this.pools.directoryPool().query('SELECT 1');
    return { status: 'ok' };
  }
}

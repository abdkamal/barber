import { Module } from '@nestjs/common';
import { StorageModule } from '../storage/storage.module';
import { CatalogController } from './catalog.controller';
import { ServicesController } from './services.controller';

@Module({
  imports: [StorageModule],
  controllers: [CatalogController, ServicesController],
})
export class CatalogModule {}

import { Module } from '@nestjs/common';
import { CatalogModule } from '../catalog/catalog.module';
import { ReportsModule } from '../reports/reports.module';
import { SchedulesModule } from '../schedules/schedules.module';
import { StorageModule } from '../storage/storage.module';
import { ProfileModule } from './profile.module';

/**
 * Aggregates every module built in milestone 4b-manager (profile/photos, catalog & services,
 * schedules/breaks/absences, reports, customer-admin extras, and media serving). Import this
 * single module into AppModule.
 */
@Module({
  imports: [ProfileModule, CatalogModule, SchedulesModule, ReportsModule, StorageModule],
})
export class ManagerFeaturesModule {}

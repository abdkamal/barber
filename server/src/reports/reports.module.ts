import { Module } from '@nestjs/common';
import { CustomerAdminController } from './customer-admin.controller';
import { ReportsController } from './reports.controller';

@Module({
  controllers: [ReportsController, CustomerAdminController],
})
export class ReportsModule {}

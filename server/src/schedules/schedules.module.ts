import { Module } from '@nestjs/common';
import { AbsencesController } from './absences.controller';
import { BreaksController } from './breaks.controller';
import { SchedulesController } from './schedules.controller';

@Module({
  controllers: [SchedulesController, BreaksController, AbsencesController],
})
export class SchedulesModule {}

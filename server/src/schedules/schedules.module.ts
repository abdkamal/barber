import { Module } from '@nestjs/common';
import { QueueModule } from '../queue.module';
import { ScheduleChangesService } from './schedule-changes.service';
import { AbsencesController } from './absences.controller';
import { BreaksController } from './breaks.controller';
import { SchedulesController } from './schedules.controller';

@Module({
  imports: [QueueModule],
  providers: [ScheduleChangesService],
  controllers: [SchedulesController, BreaksController, AbsencesController],
})
export class SchedulesModule {}

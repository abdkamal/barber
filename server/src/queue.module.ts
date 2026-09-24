import { Logger, Module } from '@nestjs/common';
import { APP_CONFIG, AppConfig } from './config/config';
import { BookingService } from './bookings/booking.service';
import { BookingsController } from './bookings/bookings.controller';
import { ManagerQueuesController } from './manager-queues/manager-queues.controller';
import { ManagerQueuesService } from './manager-queues/manager-queues.service';
import { DevicesController } from './notifications/devices.controller';
import { NotificationService } from './notifications/notification.service';
import { DisabledNotifier, FakeNotifier, FcmNotifier, fcmCredentialsFromEnv, NOTIFIER, type Notifier } from './notifications/notifier';
import { SchedulerService } from './scheduler/scheduler.service';
import { ChangeBus } from './scheduling/change-bus';
import { Clock } from './scheduling/clock';
import { PostCommit } from './scheduling/post-commit';
import { StaffDayController } from './staff-day/staff-day.controller';
import { StaffDayService } from './staff-day/staff-day.service';
import { StaffStream } from './sync/staff-stream';
import { RecoveryController } from './sync/recovery.controller';
import { SyncController } from './sync/sync.controller';
import { SyncService } from './sync/sync.service';

function notifierFor(config: AppConfig): Notifier {
  if (config.env === 'test') return new FakeNotifier();
  const creds = fcmCredentialsFromEnv();
  if (creds) return new FcmNotifier(creds);
  new Logger('Notifications').warn('FCM credentials not configured — push notifications are disabled (still recorded).');
  return new DisabledNotifier();
}

/**
 * Milestone 4b core: bookings & queues, barber endpoints, device sync + WebSocket stream,
 * the background scheduler and notifications. All salon data access goes through the
 * TenantContext of the verified token (or, for the scheduler, TenantResolver per salon).
 */
@Module({
  controllers: [BookingsController, StaffDayController, SyncController, RecoveryController, DevicesController, ManagerQueuesController],
  providers: [
    Clock,
    ChangeBus,
    { provide: NOTIFIER, inject: [APP_CONFIG], useFactory: notifierFor },
    NotificationService,
    PostCommit,
    BookingService,
    StaffDayService,
    ManagerQueuesService,
    SyncService,
    StaffStream,
    SchedulerService,
  ],
  exports: [Clock, NotificationService, PostCommit, SchedulerService],
})
export class QueueModule {}

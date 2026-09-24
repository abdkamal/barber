import { HttpStatus } from '@nestjs/common';
import { ApiError } from '../common/errors';

/** Booking / queue errors (api.md error shape). */
export const QErrors = {
  accountPending: () => new ApiError(HttpStatus.FORBIDDEN, 'ACCOUNT_PENDING', 'حسابك بانتظار اعتماد الصالون'),
  serviceUnavailable: () => new ApiError(HttpStatus.BAD_REQUEST, 'SERVICE_UNAVAILABLE', 'إحدى الخدمات المختارة غير متاحة'),
  barberNotFound: () => new ApiError(HttpStatus.NOT_FOUND, 'BARBER_NOT_FOUND', 'الحلاق غير موجود'),
  bookingClosed: () => new ApiError(HttpStatus.CONFLICT, 'BOOKING_CLOSED', 'الحجز غير متاح الآن — يُفتح لليوم نفسه قبل الافتتاح بقليل'),
  outsideHours: () => new ApiError(HttpStatus.CONFLICT, 'OUTSIDE_WORKING_HOURS', 'الوقت المطلوب خارج دوام اليوم'),
  barberAbsent: () => new ApiError(HttpStatus.CONFLICT, 'BARBER_ABSENT', 'الحلاق لن يعمل اليوم'),
  barberUnavailable: () => new ApiError(HttpStatus.CONFLICT, 'BARBER_UNAVAILABLE', 'الحجز عند هذا الحلاق متوقف مؤقتًا، جرّب حلاقًا آخر'),
  noSlot: () => new ApiError(HttpStatus.CONFLICT, 'NO_SLOT', 'لا يتسع وقت اليوم لهذه الخدمة'),
  maxActive: (n: number) =>
    new ApiError(HttpStatus.CONFLICT, 'MAX_ACTIVE_BOOKINGS', n === 1 ? 'لديك حجز نشط بالفعل' : `لا يمكن أن يكون لديك أكثر من ${n} حجوزات نشطة`),
  slotUnavailable: (message: string, details?: unknown) => new ApiError(HttpStatus.CONFLICT, 'SLOT_UNAVAILABLE', message, undefined, details),
  offerExpired: () => new ApiError(HttpStatus.GONE, 'OFFER_EXPIRED', 'انتهت مدة العرض، اطلب وقتًا جديدًا'),
  offerNotFound: () => new ApiError(HttpStatus.NOT_FOUND, 'OFFER_NOT_FOUND', 'العرض غير موجود'),
  bookingNotFound: () => new ApiError(HttpStatus.NOT_FOUND, 'BOOKING_NOT_FOUND', 'الحجز غير موجود'),
  bookingStarted: () => new ApiError(HttpStatus.CONFLICT, 'BOOKING_STARTED', 'بدأت خدمتك بالفعل'),
  bookingNotActive: () => new ApiError(HttpStatus.CONFLICT, 'BOOKING_NOT_ACTIVE', 'هذا الحجز لم يعد نشطًا'),
  alreadyCalled: () => new ApiError(HttpStatus.CONFLICT, 'BOOKING_CALLED', 'تم استدعاؤك بالفعل؛ لا يمكن تعديل الوقت الآن'),
  pastClosing: () => new ApiError(HttpStatus.CONFLICT, 'PAST_CLOSING', 'لا يتسع الوقت قبل الإغلاق لإضافة هذا الزبون'),
  notWorkingNow: () => new ApiError(HttpStatus.CONFLICT, 'NOT_WORKING_NOW', 'لا يوجد دوام لك الآن'),
  sameBarber: () => new ApiError(HttpStatus.CONFLICT, 'TRANSFER_SAME_BARBER', 'الحجز عند هذا الحلاق بالفعل'),
  barberNotWorking: () => new ApiError(HttpStatus.CONFLICT, 'BARBER_NOT_WORKING', 'الحلاق المختار ليس في دوامه اليوم'),
  transferNoSlot: (details: unknown) =>
    new ApiError(HttpStatus.CONFLICT, 'TRANSFER_NO_SLOT', 'لا يتسع وقت هذا الحلاق اليوم لهذا الحجز دون تأخير أحد', undefined, details),
  notUnfinished: () => new ApiError(HttpStatus.CONFLICT, 'BOOKING_NOT_UNFINISHED', 'هذا الحجز ليس خدمة معلّقة من يوم مُغلق'),
  invalidEndTime: () => new ApiError(HttpStatus.BAD_REQUEST, 'INVALID_END_TIME', 'وقت الانتهاء يجب أن يكون بعد بدء الخدمة وألا يتجاوز الآن'),
  invalidPhone: () => new ApiError(HttpStatus.BAD_REQUEST, 'VALIDATION_FAILED', 'رقم الهاتف غير صحيح'),
};

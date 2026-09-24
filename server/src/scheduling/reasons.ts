/**
 * Reasons recorded with every change of order or expected time (design §2 "قواعد ثابتة", ق5).
 * The code is stored; the Arabic text is what customers see («السبب: …»).
 */
export const REASONS = {
  booked: 'تم الحجز',
  customer_change: 'عدّلت وقت حجزك',
  cancelled_ahead: 'ألغى زبون قبلك حجزه',
  no_show_ahead: 'لم يحضر زبون قبلك',
  postponed_ahead: 'تأجّل زبون قبلك',
  postponed: 'تأجّل دورك لعدم حضورك',
  skipped: 'بدأ الحلاق بخدمة زبون حاضر قبلك',
  started: 'بدأت خدمة زبون قبلك',
  finished: 'انتهت خدمة الزبون الحالي',
  services_changed: 'تغيّرت خدمات زبون قبلك',
  service_overrun: 'استغرقت الخدمة الحالية وقتًا أطول من المتوقع',
  queue_moved: 'تغيّر ترتيب الطابور',
  barber_break: 'استراحة الحلاق',
  break_ended: 'انتهت استراحة الحلاق',
  closing: 'تجاوز وقت الإغلاق',
  offer_released: 'أُلغي حجز مؤقت',
  reconnected: 'وصلنا تحديث من الصالون بعد انقطاع',
  sync_conflict: 'تصحيح من جهاز الحلاق',
  walk_in: 'أُضيف زبون حاضر',
  transferred: 'نقل المدير حجزك إلى حلاق آخر',
  transferred_ahead: 'نُقل حجز زبون قبلك إلى حلاق آخر',
  day_closed: 'انتهى يوم العمل',
  barber_absent: 'الحلاق لن يعمل اليوم',
  schedule_changed: 'عدّل المدير استراحات الحلاق',
} as const;

export type ReasonCode = keyof typeof REASONS;

export function reasonText(code: string | null | undefined): string | null {
  if (!code) return null;
  return (REASONS as Record<string, string>)[code] ?? null;
}

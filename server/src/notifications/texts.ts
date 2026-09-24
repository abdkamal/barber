import { formatArabicDuration, formatArabicTime } from '../scheduling/time';

/** Arabic notification texts (design §8). */
export interface Text {
  title: string;
  body: string;
}

const nf = new Intl.NumberFormat('ar');

export const Texts = {
  bookingConfirmed: (barber: string, eta: number, tz: string): Text => ({
    title: 'تم تأكيد حجزك',
    body: `تم حجز دورك عند ${barber} — الوقت المتوقع ${formatArabicTime(eta, tz)}`,
  }),
  called: (barber: string, eta: number, tz: string): Text => ({
    title: 'اقترب دورك',
    body: `اقترب دورك عند ${barber} — يُتوقع أن تبدأ خدمتك نحو ${formatArabicTime(eta, tz)}`,
  }),
  etaChanged: (eta: number, delta: number, reason: string, tz: string): Text => ({
    title: 'تغيّر موعدك المتوقع',
    body: `تغيّر موعدك المتوقع إلى ${formatArabicTime(eta, tz)} (${delta > 0 ? 'تأخر' : 'تقدّم'} ${formatArabicDuration(delta)}) — السبب: ${reason}`,
  }),
  postponed: (steps: number, eta: number, tz: string): Text => ({
    title: 'تم تأجيل دورك',
    body: `تم تأجيل دورك ${nf.format(steps)} دور لعدم حضورك — موعدك المتوقع الآن ${formatArabicTime(eta, tz)}`,
  }),
  noShow: (): Text => ({ title: 'لم يحضر', body: 'سُجّل حجزك اليوم كـ«لم يحضر»' }),
  cancelledClosing: (reason: string): Text => ({
    title: 'أُلغي حجزك',
    body: `نعتذر، أُلغي حجزك لتجاوز وقت الإغلاق — ${reason}`,
  }),
  overrun: (customer: string): Text => ({
    title: 'تجاوز المدة',
    body: `تجاوزت خدمة ${customer} مدتها المقدرة — لا تنسَ الضغط على «إنهاء»`,
  }),
  barberNotConnected: (barber: string, since: number, tz: string): Text => ({
    title: 'حلاق لم يتصل',
    body: `لم يتصل تطبيق الحلاق ${barber} منذ بدء دوامه (${formatArabicTime(since, tz)}) — افتح شاشة الطوابير للمتابعة`,
  }),
  barberAbsent: (barber: string, open: number): Text => ({
    title: 'حلاق غائب اليوم',
    body: `أبلغ الحلاق ${barber} أنه لن يعمل اليوم — ${nf.format(open)} حجز قائم يحتاج نقلًا يدويًا من شاشة الطوابير`,
  }),
  syncConflict: (barber: string, customer: string, what: string): Text => ({
    title: 'تعارض مزامنة',
    body: `تعارض مزامنة لدى ${barber} في حجز ${customer}: ${what} — راجعه من شاشة المعلّقات`,
  }),
};

/// أدوات تنسيق الوقت والنصوص العربية المشتركة بين الشاشات.
///
/// **الأوقات تُعرض بتوقيت الصالون** (`salon.timezone` من `docs/api.md`) لا
/// بتوقيت الجهاز (design.md §2، §10؛ I5) — عبر حزمة `timezone` في
/// `saloni_api` (`core.salonHourMinute`/`core.salonAmPm`). كل الدوال هنا
/// تأخذ `timezone` وتمرره لتلك الدوال.
library;

import 'package:saloni_api/saloni_api.dart' as core;

String formatHourMinute(DateTime utc, String timezone) =>
    core.salonHourMinute(utc, timezone);

String formatAmPm(DateTime utc, String timezone) => core.salonAmPm(utc, timezone);

/// «آخر تحديث: قبل {المدة}» — design.md §8، يُعرض دائمًا. مدة نسبية فلا
/// تتأثر بالمنطقة الزمنية.
String formatAgo(DateTime since, {DateTime? now}) {
  final n = now ?? DateTime.now().toUtc();
  final d = n.difference(since);
  if (d.inSeconds < 45) return 'الآن';
  if (d.inMinutes < 1) return 'قبل لحظات';
  if (d.inMinutes < 60) return 'قبل ${d.inMinutes} دقيقة';
  final h = d.inHours;
  return 'قبل $h ${h == 1 ? 'ساعة' : 'ساعات'}';
}

String formatMinutesDelta(Duration d) {
  final m = d.inMinutes.abs();
  return '$m دقيقة';
}

String formatPrice(int cents, String currency) {
  final v = cents / 100;
  final text = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  return '$text $currency';
}

String weekdayNameArabic(int weekday) {
  // 0 = الأحد كما في اصطلاح السيرفر (docs api salon_public_profile).
  const names = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
  return names[weekday % 7];
}

String formatClockFromMinutes(int minutesSinceMidnight) {
  final total = minutesSinceMidnight % 1440;
  var h = (total ~/ 60) % 24;
  final m = (total % 60).toString().padLeft(2, '0');
  final ampm = h < 12 ? 'ص' : 'م';
  var h12 = h % 12;
  if (h12 == 0) h12 = 12;
  return '$h12:$m $ampm';
}

/// تاريخ زيارة مختصر بتوقيت الصالون: «الخميس 24/9».
String formatVisitDate(DateTime utc, String timezone) {
  final d = core.toSalonTime(utc, timezone);
  return '${weekdayNameArabic(d.weekday)} ${d.day}/${d.month}';
}

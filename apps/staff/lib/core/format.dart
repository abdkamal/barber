/// تنسيق الأوقات والمبالغ والمدد بالعربية — بأرقام غربية 0–9 دائمًا (ق41).
library;

import 'package:intl/intl.dart' show DateFormat;
import 'package:saloni_api/saloni_api.dart' as sa;

/// المنطقة الزمنية للصالون النشط — تُعرض بها كل الأوقات لا بتوقيت الجهاز
/// (design.md §2، §10؛ I5). تُضبط عند الدخول/استرجاع الجلسة
/// (`AuthController._adoptSession`/`bootstrap`/`refreshSessionInfo`).
String salonTimezone = sa.defaultSalonTimezone;

/// الأرقام دائمًا غربية 0–9 (ق41): أُلغي خيار «الأرقام العربية المشرقية».
/// تُبقى هذه الدالة نقطة مرور واحدة لكل نص رقمي معروض، وتحوّل أي رقم مشرقي
/// (مثلًا من إدخال قديم) إلى غربي.
String digits(String s) => sa.toLatinDigits(s);

/// ق41: عناصر Material المترجمة (منتقي التاريخ، التواريخ المختصرة) تستخدم
/// `DateFormat` من `intl`، وهو يعرض الأرقام المشرقية للغة `ar` افتراضيًا.
/// يُستدعى مرة عند بدء التطبيق (`main`) قبل بناء أي واجهة.
void useWesternDigitsEverywhere() {
  for (final l in const ['ar', 'ar_SA', 'ar_EG', 'ar_JO', 'ar_PS', 'ar_AE', 'ar_KW', 'ar_QA', 'ar_BH', 'ar_OM']) {
    DateFormat.useNativeDigitsByDefaultFor(l, false);
  }
}

/// «10:05» بتوقيت الصالون (بلا لاحقة).
String hhmm(DateTime t) {
  final l = sa.toSalonTime(t, salonTimezone);
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  return digits('$h:${l.minute.toString().padLeft(2, '0')}');
}

/// «ص» أو «م» بتوقيت الصالون.
String ampm(DateTime t) => sa.toSalonTime(t, salonTimezone).hour < 12 ? 'ص' : 'م';

/// «10:05 ص».
String timeAr(DateTime t) => '${hhmm(t)} ${ampm(t)}';

/// «45 د».
String minutesAr(int m) => digits('$m د');

/// مدة بشرية مختصرة: «3 د»، «1 س 20 د».
String durationAr(Duration d) {
  final m = d.inMinutes;
  if (m < 1) return 'أقل من دقيقة';
  if (m < 60) return digits('$m د');
  final h = m ~/ 60;
  final r = m % 60;
  return digits(r == 0 ? '$h س' : '$h س $r د');
}

const _weekdays = {
  DateTime.saturday: 'السبت',
  DateTime.sunday: 'الأحد',
  DateTime.monday: 'الاثنين',
  DateTime.tuesday: 'الثلاثاء',
  DateTime.wednesday: 'الأربعاء',
  DateTime.thursday: 'الخميس',
  DateTime.friday: 'الجمعة',
};

String weekdayAr(DateTime t) => _weekdays[sa.toSalonTime(t, salonTimezone).weekday]!;

/// أيام الأسبوع بترتيب يبدأ بالسبت، مع رقم Dart لكل يوم.
const List<(int, String)> weekdaysFromSaturday = [
  (DateTime.saturday, 'السبت'),
  (DateTime.sunday, 'الأحد'),
  (DateTime.monday, 'الاثنين'),
  (DateTime.tuesday, 'الثلاثاء'),
  (DateTime.wednesday, 'الأربعاء'),
  (DateTime.thursday, 'الخميس'),
  (DateTime.friday, 'الجمعة'),
];

/// العملة (ق34، ق41) — التعريف المشترك في `saloni_api` (يشمل الشيكل ₪).
typedef Currency = sa.SaloniCurrency;

/// يحلل عددًا صحيحًا من إدخال المستخدم (يقبل الأرقام المشرقية).
int? parseIntInput(String s) => int.tryParse(sa.toLatinDigits(s.trim()));

/// «HH:mm» ← دقائق منذ منتصف الليل.
String wireTime(int minutesOfDay) =>
    '${(minutesOfDay ~/ 60).toString().padLeft(2, '0')}:${(minutesOfDay % 60).toString().padLeft(2, '0')}';

/// «4:00 م» من دقائق منذ منتصف الليل — **ساعة جدارية** كما هي (دوام،
/// استراحة يومية، ساعة في تقرير): لا تحويل مناطق زمنية إطلاقًا.
///
/// إصلاح ملاحظة التجربة الأولى: كانت `displayWireTime` تبني `DateTime` بتوقيت
/// **الجهاز** ثم تحوّله لتوقيت الصالون عبر [timeAr]، فإذا اختلف توقيت الهاتف عن
/// توقيت الصالون بساعة (مثل هاتف بتوقيت فلسطين وصالون افتراضي بتوقيت الرياض)
/// ظهرت الساعة 9 المختارة «10» في كل مكان يعرض ساعات العمل.
String wallTimeAr(int minutesOfDay) {
  final m = minutesOfDay % 1440;
  final h24 = m ~/ 60;
  final h = h24 % 12 == 0 ? 12 : h24 % 12;
  return '$h:${(m % 60).toString().padLeft(2, '0')} ${h24 < 12 ? 'ص' : 'م'}';
}

/// عرض «HH:mm» القادمة من السيرفر بصيغة «4:00 م» (ساعة جدارية، انظر [wallTimeAr]).
String displayWireTime(String? hhmmWire) {
  if (hhmmWire == null || hhmmWire.isEmpty) return '—';
  final parts = sa.toLatinDigits(hhmmWire).split(':');
  final h = int.tryParse(parts[0]) ?? 0;
  final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return wallTimeAr(h * 60 + m);
}

/// أدوات توقيت الصالون (design.md §2، §10؛ I5): الأوقات تُعرض للزبون والحلاق
/// **بتوقيت الصالون** لا بتوقيت الجهاز، ويوم العمل قد يعبر منتصف الليل (ق30).
///
/// يجب استدعاء [initializeSaloniTimeZones] مرة واحدة عند بدء التطبيق قبل أي
/// استخدام لبقية هذا الملف (`tz.getLocation` يرمي قبل التهيئة).
library;

import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

bool _initialized = false;

void initializeSaloniTimeZones() {
  if (_initialized) return;
  tz_data.initializeTimeZones();
  _initialized = true;
}

/// المنطقة الزمنية الافتراضية إن غاب `timezone` عن ملف الصالون (كما في
/// `SalonPublicProfile.fromJson`).
const defaultSalonTimezone = 'Asia/Riyadh';

tz.Location _location(String timezoneName) {
  initializeSaloniTimeZones();
  try {
    return tz.getLocation(timezoneName);
  } catch (_) {
    return tz.getLocation(defaultSalonTimezone);
  }
}

/// يحوّل وقتًا (UTC أو أي `DateTime`) إلى توقيت الصالون.
tz.TZDateTime toSalonTime(DateTime utc, String timezoneName) =>
    tz.TZDateTime.from(utc, _location(timezoneName));

/// الآن بتوقيت الصالون.
tz.TZDateTime salonNow(String timezoneName, {DateTime? now}) =>
    tz.TZDateTime.from(now ?? DateTime.now().toUtc(), _location(timezoneName));

/// يبني وقتًا مطلقًا (UTC) من ساعة/دقيقة مطلوبة (منتقاة من الزبون) بحيث يقع
/// ضمن يوم عمل الحلاق (`workStartUtc` .. `workEndUtc`)، مع الالتفاف لليوم
/// التالي عندما يعبر الدوام منتصف الليل وتكون الساعة المطلوبة قبل ساعة بدء
/// الدوام (ق30). بلا دوام معروف (`workStartUtc == null`، مثل اختيار «الأسرع»
/// بلا حلاق محدد)، تُستخدم اليوم الحالي بتوقيت الصالون.
DateTime anchorRequestedTimeUtc({
  required int hour,
  required int minute,
  required String timezoneName,
  DateTime? workStartUtc,
  DateTime? workEndUtc,
  DateTime? nowUtc,
}) {
  final location = _location(timezoneName);
  if (workStartUtc == null) {
    final now = tz.TZDateTime.from(nowUtc ?? DateTime.now().toUtc(), location);
    return tz.TZDateTime(location, now.year, now.month, now.day, hour, minute).toUtc();
  }

  final start = tz.TZDateTime.from(workStartUtc, location);
  var anchorDate = tz.TZDateTime(location, start.year, start.month, start.day);

  final startMinutes = start.hour * 60 + start.minute;
  final pickedMinutes = hour * 60 + minute;

  var crossesMidnight = false;
  if (workEndUtc != null) {
    final end = tz.TZDateTime.from(workEndUtc, location);
    final sameCalendarDay =
        end.year == start.year && end.month == start.month && end.day == start.day;
    final endMinutes = end.hour * 60 + end.minute;
    crossesMidnight = !sameCalendarDay || endMinutes <= startMinutes;
  }

  if (crossesMidnight && pickedMinutes < startMinutes) {
    anchorDate = anchorDate.add(const Duration(days: 1));
  }

  return tz.TZDateTime(location, anchorDate.year, anchorDate.month, anchorDate.day, hour, minute)
      .toUtc();
}

/// «س:د» بتوقيت الصالون (بلا لاحقة ص/م)، أرقام لاتينية.
String salonHourMinute(DateTime utc, String timezoneName) {
  final t = toSalonTime(utc, timezoneName);
  var h = t.hour % 12;
  if (h == 0) h = 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// «ص» أو «م» بتوقيت الصالون.
String salonAmPm(DateTime utc, String timezoneName) =>
    toSalonTime(utc, timezoneName).hour < 12 ? 'ص' : 'م';

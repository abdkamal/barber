import 'package:saloni_api/saloni_api.dart' as sa;

import '../common/ui.dart';

/// المدير الذي يحلق أيضًا (ملاحظات التجربة الأولى — المرحلة 11).
///
/// في السيرفر يُحجز عند الموظف ويُنقل إليه الحجز (ق25) إن كان له دوام اليوم
/// (`workingStaff`). دوام الصالون الافتراضي يسري على **الحلاقين** فقط، فالمدير
/// لا يستقبل حجوزات إلا بدوام خاص له — كي لا يصبح مالك لا يحلق «حلاقًا» يُحجز
/// عنده وتصله تنبيهات عدم الاتصال. هذه الأدوات تجعل ذلك ظاهرًا وبنقرة واحدة.
abstract final class ManagerAsBarber {
  static const noScheduleReason = 'لا دوام له — دوام الصالون لا يسري على المديرين';
  static const noShiftTitle = 'لا دوام لك اليوم';
  static const noShiftBody =
      'دوام الصالون الافتراضي يسري على الحلاقين فقط. إن كنت تحلق أيضًا فاعمل بدوام الصالون: '
      'يظهر اسمك للزبائن ويُحجز عندك وتستطيع نقل الحجوزات إليك. ويمكنك تعديل أيامك لاحقًا من «الدوام».';
  static const adoptLabel = 'اعمل بدوام الصالون';
}

/// ينسخ دوام الصالون الافتراضي إلى [staffId] للأيام التي ليس له فيها دوام خاص
/// (لا يغيّر ما ضبطه مسبقًا). يعيد عدد الأيام المضافة؛ `0` = لا دوام للصالون
/// أصلًا أو كل الأيام مضبوطة.
Future<int> adoptSalonHours(sa.ApiClient api, String staffId) async {
  final rows = listOf(await api.getManagerSchedules());
  final own = {
    for (final r in rows)
      if (str(r, ['staffId']) == staffId) intOf(r, ['weekday']),
  };
  var added = 0;
  for (final r in rows) {
    if (r['staffId'] != null) continue;
    final weekday = intOf(r, ['weekday']);
    if (weekday == null || own.contains(weekday)) continue;
    await api.putManagerSchedule(
      staffId: staffId,
      weekday: weekday,
      opensAt: str(r, ['opensAt']),
      closesAt: str(r, ['closesAt']),
    );
    added++;
  }
  return added;
}

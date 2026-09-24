import 'package:saloni_api/saloni_api.dart';
import 'package:test/test.dart';

void main() {
  group('anchorRequestedTimeUtc', () {
    test('shift 18:00–02:00 (يعبر منتصف الليل): طلب 00:30 عند 23:30 يلتف لليوم التالي', () {
      // دوام الحلاق: اليوم 18:00 — غدًا 02:00 بتوقيت الرياض (UTC+3).
      final workStart = DateTime.utc(2026, 9, 24, 15, 0); // 18:00 بتوقيت الرياض
      final workEnd = DateTime.utc(2026, 9, 25, 23, 0); // 02:00 بتوقيت الرياض (اليوم التالي)
      final result = anchorRequestedTimeUtc(
        hour: 0,
        minute: 30,
        timezoneName: 'Asia/Riyadh',
        workStartUtc: workStart,
        workEndUtc: workEnd,
      );
      // 00:30 بتوقيت الرياض في اليوم التالي (25/9) = 21:30 UTC في 24/9.
      expect(result, DateTime.utc(2026, 9, 24, 21, 30));
      expect(result.isAfter(workStart), isTrue);
      expect(result.isBefore(workEnd), isTrue);
    });

    test('نفس المثال: طلب 19:00 (قبل منتصف الليل) يبقى في يوم بدء الدوام', () {
      final workStart = DateTime.utc(2026, 9, 24, 15, 0); // 18:00 الرياض
      final workEnd = DateTime.utc(2026, 9, 25, 23, 0); // 02:00 الرياض غدًا
      final result = anchorRequestedTimeUtc(
        hour: 19,
        minute: 0,
        timezoneName: 'Asia/Riyadh',
        workStartUtc: workStart,
        workEndUtc: workEnd,
      );
      expect(result, DateTime.utc(2026, 9, 24, 16, 0)); // 19:00 الرياض نفس اليوم
    });

    test('دوام لا يعبر منتصف الليل: ساعة قبل البدء لا تُلتف لليوم التالي', () {
      final workStart = DateTime.utc(2026, 9, 24, 6, 0); // 09:00 الرياض
      final workEnd = DateTime.utc(2026, 9, 24, 15, 0); // 18:00 الرياض
      final result = anchorRequestedTimeUtc(
        hour: 8,
        minute: 0,
        timezoneName: 'Asia/Riyadh',
        workStartUtc: workStart,
        workEndUtc: workEnd,
      );
      expect(result, DateTime.utc(2026, 9, 24, 5, 0)); // 08:00 الرياض نفس اليوم
    });

    test('جهاز بمنطقة زمنية مختلفة: التثبيت بتوقيت الصالون لا الجهاز (لا يتأثر بـ nowUtc)', () {
      // الآن فعليًا 23:30 بتوقيت الرياض، لكن دالة التثبيت لا تعتمد على وقت
      // الجهاز إطلاقًا عند وجود دوام حلاق — فقط على workStart/workEnd
      // بتوقيت الصالون، بصرف النظر عن أي منطقة زمنية يقيم فيها الجهاز.
      final workStart = DateTime.utc(2026, 9, 24, 15, 0); // 18:00 الرياض
      final workEnd = DateTime.utc(2026, 9, 25, 23, 0); // 02:00 الرياض غدًا
      final resultFromTokyoDevice = anchorRequestedTimeUtc(
        hour: 0,
        minute: 30,
        timezoneName: 'Asia/Riyadh',
        workStartUtc: workStart,
        workEndUtc: workEnd,
        // وقت جهاز مختلف تمامًا (لا يُستخدم إلا كاحتياط بلا دوام معروف).
        nowUtc: DateTime.utc(2026, 9, 24, 3, 0),
      );
      expect(resultFromTokyoDevice, DateTime.utc(2026, 9, 24, 21, 30));
    });

    test('بلا حلاق محدد (fastest): يُستخدم تاريخ اليوم بتوقيت الصالون', () {
      final result = anchorRequestedTimeUtc(
        hour: 10,
        minute: 0,
        timezoneName: 'Asia/Riyadh',
        nowUtc: DateTime.utc(2026, 9, 24, 5, 0), // 08:00 الرياض
      );
      expect(result, DateTime.utc(2026, 9, 24, 7, 0)); // 10:00 الرياض نفس اليوم
    });
  });

  group('عرض الوقت بتوقيت الصالون', () {
    test('salonHourMinute/salonAmPm يعكسان توقيت الصالون بصرف النظر عن توقيت الجهاز', () {
      final utc = DateTime.utc(2026, 9, 24, 21, 30); // 00:30 الرياض
      expect(salonHourMinute(utc, 'Asia/Riyadh'), '12:30');
      expect(salonAmPm(utc, 'Asia/Riyadh'), 'ص');

      // نفس اللحظة بتوقيت طوكيو (UTC+9) تكون 06:30 صباحًا — مختلفة تمامًا.
      expect(salonHourMinute(utc, 'Asia/Tokyo'), '6:30');
      expect(salonAmPm(utc, 'Asia/Tokyo'), 'ص');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_api/saloni_api.dart' show initializeSaloniTimeZones;
import 'package:saloni_staff/core/format.dart' as fmt;

void main() {
  initializeSaloniTimeZones();

  tearDown(() {
    fmt.salonTimezone = 'Asia/Riyadh';
  });

  group('عرض الوقت بتوقيت الصالون (I5)', () {
    test('hhmm/ampm يعكسان توقيت الصالون بصرف النظر عن أي منطقة زمنية أخرى', () {
      fmt.salonTimezone = 'Asia/Riyadh';
      final utc = DateTime.utc(2026, 9, 24, 21, 30); // 00:30 بتوقيت الرياض
      expect(fmt.hhmm(utc), '12:30');
      expect(fmt.ampm(utc), 'ص');
    });

    test('تغيّر توقيت الصالون (مثلًا صالون بمنطقة أخرى) ينعكس فورًا على العرض', () {
      // نفس اللحظة، لكن الصالون في طوكيو بدل الرياض — يجب أن يختلف المعروض.
      final utc = DateTime.utc(2026, 9, 24, 21, 30);
      fmt.salonTimezone = 'Asia/Riyadh';
      final riyadh = fmt.hhmm(utc);
      fmt.salonTimezone = 'Asia/Tokyo';
      final tokyo = fmt.hhmm(utc);
      expect(riyadh, isNot(tokyo));
      expect(tokyo, '6:30');
    });
  });
}

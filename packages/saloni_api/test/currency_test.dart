import 'package:saloni_api/saloni_api.dart';
import 'package:test/test.dart';

void main() {
  group('SaloniCurrency (ق34، ق41)', () {
    test('الشيكل ILS: الرمز ₪ ومنزلتان، بلا علم', () {
      final c = SaloniCurrency.of('ILS');
      expect(c.symbol, '₪');
      expect(c.minorDigits, 2);
      expect(c.format(4550), '45.50 ₪');
      expect(c.format(4500), '45 ₪');
      expect(SaloniCurrency.supported.map((c) => c.code), contains('ILS'));
      // لا أعلام (رموز Regional Indicator) في أي رمز أو اسم عملة.
      for (final c in SaloniCurrency.supported) {
        final all = '${c.symbol}${c.nameAr}';
        expect(all.runes.any((r) => r >= 0x1F1E6 && r <= 0x1F1FF), isFalse, reason: c.code);
      }
    });

    test('ثلاث منازل للدينار الكويتي، وتجميع الآلاف بأرقام غربية', () {
      expect(SaloniCurrency.of('kwd').format(1250500), '1,250.500 د.ك');
      expect(SaloniCurrency.of('SAR').amount(123456700), '1,234,567');
    });

    test('الإدخال بالأرقام المشرقية يُقبل', () {
      expect(SaloniCurrency.of('SAR').parse('٦٠٫٥'), 6050);
      expect(SaloniCurrency.of('ILS').parse('12'), 1200);
      expect(SaloniCurrency.of('ILS').parse('abc'), isNull);
    });

    test('رمز معروض قديم («ر.س») يُتعرّف عليه، والمجهول يُعرض كما هو', () {
      expect(SaloniCurrency.of('ر.س').code, 'SAR');
      expect(SaloniCurrency.of('CHF').symbol, 'CHF');
      expect(SaloniCurrency.of(null).code, 'SAR');
    });
  });

  group('أرقام الهاتف الدولية (واتساب)', () {
    test('يقبل أي رمز دولة يكتبه المستخدم', () {
      expect(normalizeInternationalPhone('+970 59 123 4567'), '+970591234567');
      expect(normalizeInternationalPhone('00972-50-123-4567'), '+972501234567');
      expect(normalizeInternationalPhone('+1 (415) 555-0100'), '+14155550100');
      expect(normalizeInternationalPhone('+٩٦٦٥٠١٢٣٤٥٦٧'), '+966501234567');
    });

    test('يرفض الرقم المحلي بلا رمز دولة والرقم غير الصالح', () {
      expect(normalizeInternationalPhone('0591234567'), isNull);
      expect(normalizeInternationalPhone('+0591234567'), isNull);
      expect(normalizeInternationalPhone('+12345'), isNull);
      expect(normalizeInternationalPhone('+1234567890123456'), isNull);
    });

    test('رابط wa.me بالأرقام فقط', () {
      expect(whatsappUri('+970591234567').toString(), 'https://wa.me/970591234567');
    });
  });

  test('toLatinDigits', () {
    expect(toLatinDigits('١٢:٣٠ ۴'), '12:30 4');
  });

  test('salonWallTimeToUtc يستخدم توقيت الصالون لا الجهاز', () {
    expect(
      salonWallTimeToUtc(year: 2026, month: 1, day: 10, minutesOfDay: 13 * 60, timezoneName: 'Asia/Riyadh'),
      DateTime.utc(2026, 1, 10, 10, 0),
    );
    // الخليل: UTC+2 شتاءً.
    expect(
      salonWallTimeToUtc(year: 2026, month: 1, day: 10, minutesOfDay: 9 * 60, timezoneName: 'Asia/Hebron'),
      DateTime.utc(2026, 1, 10, 7, 0),
    );
  });
}

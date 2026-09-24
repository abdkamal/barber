/// تنسيق الأوقات والمبالغ والمدد بالعربية (design.md §10: اختيار نمط الأرقام).
library;

/// نمط الأرقام المعروض — يضبطه الإعداد «الأرقام العربية المشرقية».
enum NumeralStyle { latin, eastern }

/// الإعداد الحالي لنمط الأرقام (يُضبط من التفضيلات عند بدء التطبيق).
NumeralStyle numeralStyle = NumeralStyle.latin;

const _eastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

/// يحوّل الأرقام اللاتينية في النص إلى المشرقية إن كان الإعداد مفعّلًا.
String digits(String s) {
  if (numeralStyle == NumeralStyle.latin) return s;
  final b = StringBuffer();
  for (final ch in s.runes) {
    if (ch >= 0x30 && ch <= 0x39) {
      b.write(_eastern[ch - 0x30]);
    } else {
      b.writeCharCode(ch);
    }
  }
  return b.toString();
}

/// «10:05» بالتوقيت المحلي للجهاز (بلا لاحقة).
String hhmm(DateTime t) {
  final l = t.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  return digits('$h:${l.minute.toString().padLeft(2, '0')}');
}

/// «ص» أو «م».
String ampm(DateTime t) => t.toLocal().hour < 12 ? 'ص' : 'م';

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

String weekdayAr(DateTime t) => _weekdays[t.toLocal().weekday]!;

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

/// العملة: الرمز العربي ومنازل الوحدة الصغرى (api.md: المبالغ بأصغر وحدة).
class Currency {
  const Currency(this.code, this.symbol, this.minorDigits);
  final String code;
  final String symbol;
  final int minorDigits;

  static const _known = {
    'SAR': Currency('SAR', 'ر.س', 2),
    'AED': Currency('AED', 'د.إ', 2),
    'QAR': Currency('QAR', 'ر.ق', 2),
    'KWD': Currency('KWD', 'د.ك', 3),
    'BHD': Currency('BHD', 'د.ب', 3),
    'OMR': Currency('OMR', 'ر.ع', 3),
    'JOD': Currency('JOD', 'د.أ', 3),
    'EGP': Currency('EGP', 'ج.م', 2),
    'USD': Currency('USD', r'$', 2),
  };

  static Currency of(String? code) =>
      _known[code?.toUpperCase()] ?? Currency(code ?? 'SAR', code ?? 'ر.س', 2);

  int get _factor => minorDigits == 3 ? 1000 : 100;

  /// «60» أو «60.50» (بلا رمز).
  String amount(int minor) {
    final whole = minor ~/ _factor;
    final frac = minor % _factor;
    final w = _group(whole);
    if (frac == 0) return digits(w);
    return digits('$w.${frac.toString().padLeft(minorDigits, '0')}');
  }

  /// «60 ر.س».
  String format(int minor) => '${amount(minor)} $symbol';

  /// يحوّل نصًا مُدخلًا («60» أو «60.5») إلى الوحدة الصغرى.
  int? parse(String text) {
    final t = text.trim().replaceAll(',', '');
    final v = double.tryParse(_toLatin(t));
    if (v == null || v < 0) return null;
    return (v * _factor).round();
  }

  static String _group(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

/// يحوّل الأرقام المشرقية المُدخلة إلى لاتينية.
String _toLatin(String s) {
  var out = s;
  for (var i = 0; i < 10; i++) {
    out = out.replaceAll(_eastern[i], '$i');
  }
  return out;
}

/// يحلل عددًا صحيحًا من إدخال المستخدم (يقبل الأرقام المشرقية).
int? parseIntInput(String s) => int.tryParse(_toLatin(s.trim()));

/// «HH:mm» ← دقائق منذ منتصف الليل.
String wireTime(int minutesOfDay) =>
    '${(minutesOfDay ~/ 60).toString().padLeft(2, '0')}:${(minutesOfDay % 60).toString().padLeft(2, '0')}';

/// عرض «HH:mm» القادمة من السيرفر بصيغة «4:00 م».
String displayWireTime(String? hhmmWire) {
  if (hhmmWire == null || hhmmWire.isEmpty) return '—';
  final parts = hhmmWire.split(':');
  final h = int.tryParse(parts[0]) ?? 0;
  final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  final d = DateTime(2000, 1, 1, h, m);
  return timeAr(d);
}

/// العملات وتنسيق المبالغ المشترك بين التطبيقين (ق34، ق41).
///
/// - المبالغ على السلك بأصغر وحدة (`docs/api.md`): هللة، فلس، أغورة...
/// - **الأرقام دائمًا غربية 0–9** (ق41) — لا يُستخدم `intl` هنا أصلًا، والإدخال
///   بالأرقام المشرقية يُقبل ويُحوَّل.
/// - **لا أعلام دول** في أي مكان؛ الرمز (مثل ₪) هو العلامة البصرية للعملة.
library;

/// عملة معروفة: الرمز المعروض، الاسم العربي، ومنازل الوحدة الصغرى، ومنطقة
/// زمنية مقترحة عند إنشاء صالون بها (تُعدَّل في شاشة التسجيل).
class SaloniCurrency {
  const SaloniCurrency(this.code, this.symbol, this.minorDigits, {this.nameAr = '', this.defaultTimezone});

  /// رمز ISO 4217، مثل `SAR`.
  final String code;

  /// الرمز المعروض بجانب المبلغ، مثل «ر.س» أو «₪».
  final String symbol;

  /// منازل الوحدة الصغرى (2 أو 3).
  final int minorDigits;
  final String nameAr;
  final String? defaultTimezone;

  /// العملات المعروضة عند تسجيل صالون، بالترتيب.
  static const List<SaloniCurrency> supported = [
    SaloniCurrency('SAR', 'ر.س', 2, nameAr: 'ريال سعودي', defaultTimezone: 'Asia/Riyadh'),
    SaloniCurrency('AED', 'د.إ', 2, nameAr: 'درهم إماراتي', defaultTimezone: 'Asia/Dubai'),
    SaloniCurrency('KWD', 'د.ك', 3, nameAr: 'دينار كويتي', defaultTimezone: 'Asia/Kuwait'),
    SaloniCurrency('QAR', 'ر.ق', 2, nameAr: 'ريال قطري', defaultTimezone: 'Asia/Qatar'),
    SaloniCurrency('BHD', 'د.ب', 3, nameAr: 'دينار بحريني', defaultTimezone: 'Asia/Bahrain'),
    SaloniCurrency('OMR', 'ر.ع', 3, nameAr: 'ريال عماني', defaultTimezone: 'Asia/Muscat'),
    SaloniCurrency('JOD', 'د.أ', 3, nameAr: 'دينار أردني', defaultTimezone: 'Asia/Amman'),
    SaloniCurrency('EGP', 'ج.م', 2, nameAr: 'جنيه مصري', defaultTimezone: 'Africa/Cairo'),
    SaloniCurrency('ILS', '₪', 2, nameAr: 'شيكل', defaultTimezone: 'Asia/Hebron'),
    SaloniCurrency('USD', r'$', 2, nameAr: 'دولار أمريكي'),
  ];

  /// العملة من رمزها. غير المعروف: رمز من 3 أحرف لاتينية يُعرض كما هو
  /// بمنزلتين؛ وأي نص آخر (مثل «ر.س» في بيانات قديمة) يُعامل كرمز معروض.
  static SaloniCurrency of(String? codeOrSymbol) {
    final raw = (codeOrSymbol ?? '').trim();
    if (raw.isEmpty) return supported.first;
    final up = raw.toUpperCase();
    for (final c in supported) {
      if (c.code == up || c.symbol == raw) return c;
    }
    return SaloniCurrency(up, RegExp(r'^[A-Z]{3}$').hasMatch(up) ? up : raw, 2);
  }

  int get _factor => minorDigits == 3 ? 1000 : 100;

  /// «60» أو «1,250.50» (بلا رمز، أرقام غربية).
  String amount(int minor) {
    final neg = minor < 0;
    final m = minor.abs();
    final whole = m ~/ _factor;
    final frac = m % _factor;
    final w = _group(whole);
    final s = frac == 0 ? w : '$w.${frac.toString().padLeft(minorDigits, '0')}';
    return neg ? '-$s' : s;
  }

  /// «60 ر.س» / «45 ₪».
  String format(int minor) => '${amount(minor)} $symbol';

  /// يحوّل نصًا مُدخلًا («60» أو «60.5» أو «٦٠») إلى الوحدة الصغرى.
  int? parse(String text) {
    final t = toLatinDigits(text.trim()).replaceAll(',', '').replaceAll('٫', '.');
    final v = double.tryParse(t);
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

/// يحوّل الأرقام العربية المشرقية (٠–٩) والفارسية (۰–۹) إلى غربية 0–9.
String toLatinDigits(String s) {
  final b = StringBuffer();
  for (final ch in s.runes) {
    if (ch >= 0x0660 && ch <= 0x0669) {
      b.writeCharCode(0x30 + ch - 0x0660);
    } else if (ch >= 0x06F0 && ch <= 0x06F9) {
      b.writeCharCode(0x30 + ch - 0x06F0);
    } else {
      b.writeCharCode(ch);
    }
  }
  return b.toString();
}

/// يطبّع رقم واتساب/هاتف دولي: أرقام غربية، يحذف المسافات والشرطات والأقواس،
/// «00» في البداية ← «+». يعيد `+` متبوعة بـ 8–15 رقمًا (أولها ليس صفرًا —
/// صيغة E.164) أو `null` إن لم يكن رقمًا دوليًا كاملًا.
String? normalizeInternationalPhone(String input) {
  var s = toLatinDigits(input.trim()).replaceAll(RegExp('[\\s\\-.()\\u200e\\u200f\\u202a-\\u202e]'), '');
  if (s.startsWith('00')) s = '+${s.substring(2)}';
  return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(s) ? s : null;
}

/// رابط محادثة واتساب: `https://wa.me/<الأرقام فقط، بلا +>`.
Uri whatsappUri(String number) =>
    Uri.parse('https://wa.me/${toLatinDigits(number).replaceAll(RegExp(r'\D'), '')}');

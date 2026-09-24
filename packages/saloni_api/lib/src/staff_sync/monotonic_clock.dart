/// ساعة رتيبة لحساب وقت حدوث أحداث الجهاز — design.md §6.2:
/// «وقت السيرفر عند آخر مزامنة + (الوقت المنقضي منذها بساعة الجهاز التي لا
/// تتأثر بتغيير الوقت). إذا أُعيد تشغيل الجهاز أثناء الانقطاع يُعلَّم الحدث
/// «توقيت تقريبي»».
///
/// تُستخدم `Stopwatch` (رتيبة، لا تتأثر بتغيير ساعة النظام) لقياس الوقت
/// المنقضي منذ آخر تثبيت (anchor) حقيقي حدث في هذه الجلسة الحيّة للتطبيق.
/// عند استرجاع مرساة محفوظة من تشغيل سابق (`restoreAnchor`) لا يمكن ضمان
/// استمرارية الساعة الرتيبة عبر إعادة التشغيل، فتُعلَّم كل القراءات
/// بـ`approximate: true` حتى تحدث مزامنة حقيقية جديدة (`anchor`) في هذا
/// التشغيل.
class ClockReading {
  const ClockReading(this.occurredAt, {required this.approximate});

  final DateTime occurredAt;
  final bool approximate;
}

class MonotonicClock {
  MonotonicClock({Stopwatch? stopwatch})
      : _stopwatch = stopwatch ?? (Stopwatch()..start());

  final Stopwatch _stopwatch;

  DateTime? _anchorServerTime;
  Duration? _anchorElapsed;
  bool _liveAnchor = false;

  /// تثبيت حقيقي حدث الآن (استجابة مزامنة/نبضة وصلت فعلًا في هذا التشغيل).
  /// القراءات بعده غير تقريبية حتى إعادة تشغيل التطبيق.
  void anchor(DateTime serverTime) {
    _anchorServerTime = serverTime;
    _anchorElapsed = _stopwatch.elapsed;
    _liveAnchor = true;
  }

  /// استرجاع مرساة محفوظة من تشغيل سابق (عند بدء التطبيق، قبل أي مزامنة
  /// حقيقية في هذا التشغيل). القراءات المبنية عليها تُعلَّم تقريبية دائمًا
  /// حتى يحدث `anchor` جديد.
  void restoreAnchor(DateTime serverTime) {
    _anchorServerTime = serverTime;
    _anchorElapsed = _stopwatch.elapsed;
    _liveAnchor = false;
  }

  bool get hasAnchor => _anchorServerTime != null;

  ClockReading now() {
    final anchorTime = _anchorServerTime;
    if (anchorTime == null) {
      // لا مرساة مطلقًا بعد — رجوع لساعة النظام كحل أخير، مع تعليمه تقريبيًا.
      return ClockReading(DateTime.now().toUtc(), approximate: true);
    }
    final elapsedSinceAnchor = _stopwatch.elapsed - _anchorElapsed!;
    return ClockReading(
      anchorTime.add(elapsedSinceAnchor),
      approximate: !_liveAnchor,
    );
  }
}

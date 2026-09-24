import 'boot_clock.dart';

/// ساعة رتيبة لحساب وقت حدوث أحداث الجهاز — design.md §6.2:
/// «وقت السيرفر عند آخر مزامنة + (الوقت المنقضي منذها بساعة الجهاز التي لا
/// تتأثر بتغيير الوقت). إذا أُعيد تشغيل الجهاز أثناء الانقطاع يُعلَّم الحدث
/// «توقيت تقريبي»».
///
/// الوقت المنقضي منذ المرساة يُقاس بساعة التشغيل ([BootReading]) إن مُرّرت
/// قراءتها (تشمل نوم الجهاز وإغلاق التطبيق)، وإلا بـ`Stopwatch` (رتيبة داخل
/// تشغيل التطبيق الحي فقط).
///
/// ق40 (مراجعة F1) عند بدء التطبيق (`restoreAnchor`):
/// - **الجهاز لم يُعد تشغيله** (قراءة التشغيل الحالية من التشغيل نفسه ولم
///   تنقص عن المحفوظة): المرساة = وقت السيرفر المحفوظ + الفرق بين القراءتين —
///   يُحسب وقت إغلاق التطبيق، والأوقات **دقيقة** (غير تقريبية).
/// - **أُعيد تشغيله** (أو لا قراءة): المرساة = ساعة الجهاز، **ولا تسبق** آخر
///   وقت سيرفر معروف، والأوقات **تقريبية** حتى تحدث مزامنة حقيقية (`anchor`).
class ClockReading {
  const ClockReading(this.occurredAt, {required this.approximate});

  final DateTime occurredAt;
  final bool approximate;
}

class MonotonicClock {
  MonotonicClock({Stopwatch? stopwatch, DateTime Function()? wallClock})
      : _stopwatch = stopwatch ?? (Stopwatch()..start()),
        _wall = wallClock ?? (() => DateTime.now().toUtc());

  final Stopwatch _stopwatch;
  final DateTime Function() _wall;

  DateTime? _anchorServerTime;
  Duration? _anchorElapsed;
  BootReading? _anchorBoot;
  bool _approximate = true;

  /// تثبيت حقيقي حدث الآن (استجابة مزامنة/نبضة وصلت فعلًا في هذا التشغيل)،
  /// مع قراءة ساعة التشغيل في اللحظة نفسها إن توفرت. القراءات بعده دقيقة.
  void anchor(DateTime serverTime, {BootReading? boot}) {
    _anchorServerTime = serverTime;
    _anchorElapsed = _stopwatch.elapsed;
    _anchorBoot = boot;
    _approximate = false;
  }

  /// استرجاع مرساة محفوظة من تشغيل سابق للتطبيق (قبل أي مزامنة حقيقية في
  /// هذا التشغيل). [savedBoot] قراءة ساعة التشغيل المحفوظة معها،
  /// و[currentBoot] قراءتها الآن.
  void restoreAnchor(
    DateTime serverTime, {
    BootReading? savedBoot,
    BootReading? currentBoot,
  }) {
    if (savedBoot != null && currentBoot != null && currentBoot.sameBootAs(savedBoot)) {
      // التطبيق أُغلق وأُعيد فتحه والجهاز لم يُعد تشغيله: الفرق يغطي وقت الإغلاق.
      final gap = currentBoot.sinceBoot - savedBoot.sinceBoot;
      _anchorServerTime = serverTime;
      _anchorBoot = savedBoot;
      _anchorElapsed = _stopwatch.elapsed - gap;
      _approximate = false;
      return;
    }
    // أُعيد تشغيل الجهاز (أو لا قراءة): ساعة الجهاز، لا قبل آخر وقت سيرفر.
    final wall = _wall().toUtc();
    _anchorServerTime = wall.isAfter(serverTime) ? wall : serverTime;
    _anchorElapsed = _stopwatch.elapsed;
    _anchorBoot = currentBoot;
    _approximate = true;
  }

  bool get hasAnchor => _anchorServerTime != null;

  /// وقت الحدث الآن. [boot] قراءة ساعة التشغيل الحالية إن توفرت (أدق من
  /// `Stopwatch` لأنها تشمل نوم الجهاز).
  ClockReading now([BootReading? boot]) {
    final anchorTime = _anchorServerTime;
    if (anchorTime == null) {
      // لا مرساة مطلقًا بعد — رجوع لساعة النظام كحل أخير، مع تعليمه تقريبيًا.
      return ClockReading(_wall().toUtc(), approximate: true);
    }
    final anchorBoot = _anchorBoot;
    final elapsed = (boot != null && anchorBoot != null && boot.sameBootAs(anchorBoot))
        ? boot.sinceBoot - anchorBoot.sinceBoot
        : _stopwatch.elapsed - _anchorElapsed!;
    return ClockReading(anchorTime.add(elapsed), approximate: _approximate);
  }
}

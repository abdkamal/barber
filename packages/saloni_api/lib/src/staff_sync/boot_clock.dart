/// ساعة «الوقت المنقضي منذ تشغيل الجهاز» — ق40 (مراجعة F1): تستمر عبر إغلاق
/// التطبيق وإعادة فتحه، وتشمل وقت نوم الجهاز، ولا تتأثر بتغيير ساعة النظام
/// (أندرويد: `SystemClock.elapsedRealtime`). تُحفظ قراءتها مع مرساة الساعة، فإذا
/// أُعيد فتح التطبيق دون إعادة تشغيل الجهاز يُحسب الوقت المنقضي بدقة (غير تقريبي).
///
/// التطبيق يحقن تنفيذًا حقيقيًا (قناة منصة في تطبيق الطاقم)؛ الاختبارات تحقن
/// ساعة مزيفة؛ وحيث لا تتوفر (`NoBootClock`) يبقى السلوك القديم: بعد إعادة فتح
/// التطبيق تُعلَّم الأوقات تقريبية.
class BootReading {
  const BootReading(this.sinceBoot, {this.bootId});

  /// الوقت المنقضي منذ تشغيل الجهاز.
  final Duration sinceBoot;

  /// معرّف تشغيل الجهاز إن توفر (عدّاد مرات التشغيل…) — يكشف إعادة التشغيل
  /// حتى لو صارت القراءة الجديدة أكبر من المحفوظة.
  final String? bootId;

  /// نفس تشغيل الجهاز الذي أُخذت فيه [earlier]: المعرّف نفسه (إن عُرف
  /// للطرفين) والقراءة لم تنقص.
  bool sameBootAs(BootReading earlier) =>
      (bootId == null || earlier.bootId == null || bootId == earlier.bootId) &&
      sinceBoot >= earlier.sinceBoot;

  Map<String, dynamic> toJson() => {
        'sinceBootMs': sinceBoot.inMilliseconds,
        if (bootId != null) 'bootId': bootId,
      };

  static BootReading? fromJson(Object? json) {
    if (json is! Map) return null;
    final ms = json['sinceBootMs'];
    if (ms is! num) return null;
    final id = json['bootId'];
    return BootReading(Duration(milliseconds: ms.toInt()),
        bootId: id is String ? id : null);
  }

  @override
  bool operator ==(Object other) =>
      other is BootReading && other.sinceBoot == sinceBoot && other.bootId == bootId;

  @override
  int get hashCode => Object.hash(sinceBoot, bootId);

  @override
  String toString() => 'BootReading($sinceBoot, bootId: $bootId)';
}

/// مصدر [BootReading]؛ `null` = غير متاح على هذا الجهاز/المنصة.
abstract class BootClock {
  Future<BootReading?> read();
}

/// لا ساعة تشغيل (Dart خالص، iOS، الاختبارات التي لا تحتاجها).
class NoBootClock implements BootClock {
  const NoBootClock();

  @override
  Future<BootReading?> read() async => null;
}

/// مرساة الساعة المحفوظة: وقت السيرفر عند آخر مزامنة، وقراءة ساعة التشغيل
/// في اللحظة نفسها (تُحفظان معًا ذرّيًا).
class ClockAnchorRecord {
  const ClockAnchorRecord(this.serverTime, {this.boot});

  final DateTime serverTime;
  final BootReading? boot;

  Map<String, dynamic> toJson() => {
        'serverTime': serverTime.toUtc().toIso8601String(),
        if (boot != null) 'boot': boot!.toJson(),
      };

  static ClockAnchorRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final t = DateTime.tryParse(json['serverTime'] as String? ?? '');
    if (t == null) return null;
    return ClockAnchorRecord(t.toUtc(), boot: BootReading.fromJson(json['boot']));
  }
}

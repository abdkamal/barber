import 'package:flutter/services.dart';
import 'package:saloni_api/staff_sync.dart';

/// ق40 (مراجعة F1): ساعة «منذ تشغيل الجهاز» عبر قناة المنصة `saloni/boot_clock`
/// (أندرويد: `SystemClock.elapsedRealtime` + عدّاد مرات التشغيل، في
/// `MainActivity.kt`). حيث لا تتوفر (iOS، الاختبارات، أي خطأ) تعيد `null`
/// فيبقى السلوك القديم (أوقات تقريبية بعد إعادة فتح التطبيق دون اتصال).
class PlatformBootClock implements BootClock {
  const PlatformBootClock();

  static const _channel = MethodChannel('saloni/boot_clock');

  @override
  Future<BootReading?> read() async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('read');
      final ms = m?['sinceBootMs'];
      if (ms is! num) return null;
      final id = m?['bootId'];
      return BootReading(Duration(milliseconds: ms.toInt()), bootId: id is String ? id : null);
    } catch (_) {
      return null;
    }
  }
}

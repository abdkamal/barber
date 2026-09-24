/// إعدادات البيئة — تُمرَّر عبر `--dart-define` عند البناء أو التشغيل.
///
/// مثال:
/// `flutter run --dart-define=SALONI_API_BASE_URL=https://api.example.com`
abstract final class Env {
  /// عنوان السيرفر الأساسي. القيمة الافتراضية تناسب محاكي أندرويد
  /// (`10.0.2.2` يوصل لـ`localhost` على جهاز التطوير).
  static const apiBaseUrl = String.fromEnvironment(
    'SALONI_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );
}

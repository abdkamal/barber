/// إعدادات التشغيل عبر `--dart-define` (انظر README).
abstract final class AppConfig {
  /// عنوان السيرفر. الافتراضي يناسب محاكي أندرويد مع سيرفر محلي على المنفذ 3000.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  /// تفعيل إشعارات Firebase (يتطلب `android/app/google-services.json`).
  static const bool fcmEnabled = bool.fromEnvironment('FCM_ENABLED');

  /// فاصل النبضة والمزامنة (design.md §11: 30 ث).
  static const Duration heartbeat = Duration(seconds: 30);

  static const String appLabel = 'صالوني — الطاقم';

  /// اسم التطبيق كما يظهر في «عن التطبيق».
  static const String appName = 'صالوني — احجز دوري';

  /// إصدار التطبيق — يطابق `version` في pubspec.yaml (لا تُستخدم حزمة
  /// package_info). يمكن تجاوزه عند البناء: `--dart-define=APP_VERSION=…`.
  static const String appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0 (1)');
}

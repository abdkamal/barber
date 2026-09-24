import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:saloni_api/staff_sync.dart' show BootClock, NoBootClock;

import 'boot_clock.dart';

/// خدمات الجهاز: الخدمة الأمامية (design.md §1) وإذن الإشعارات (ق31، §8).
/// تُستبدل في الاختبارات بـ[NoopDeviceServices].
abstract class DeviceServices {
  /// هل الإشعارات مسموحة؟ (`null` = غير معروف على هذه المنصة).
  Future<bool?> notificationsAllowed();

  /// يطلب الإذن ويعيد النتيجة.
  Future<bool?> requestNotifications();

  /// يطلب استثناء التطبيق من تحسين البطارية كي لا يوقف أندرويد المزامنة.
  Future<void> requestBatteryExemption();

  /// يبدأ الخدمة الأمامية بإشعار دائم يُبقي المزامنة حيّة.
  Future<void> startKeepAlive({required String title, required String text});

  Future<void> updateKeepAlive({required String title, required String text});

  Future<void> stopKeepAlive();

  /// ق40 (مراجعة F1): ساعة «منذ تشغيل الجهاز» لمحرك المزامنة.
  BootClock get bootClock;
}

class NoopDeviceServices implements DeviceServices {
  const NoopDeviceServices({this.allowed, this.bootClock = const NoBootClock()});
  final bool? allowed;
  @override
  final BootClock bootClock;
  @override
  Future<bool?> notificationsAllowed() async => allowed;
  @override
  Future<bool?> requestNotifications() async => allowed;
  @override
  Future<void> requestBatteryExemption() async {}
  @override
  Future<void> startKeepAlive({required String title, required String text}) async {}
  @override
  Future<void> updateKeepAlive({required String title, required String text}) async {}
  @override
  Future<void> stopKeepAlive() async {}
}

DeviceServices defaultDeviceServices() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return AndroidDeviceServices();
  }
  return const NoopDeviceServices();
}

/// نقطة دخول معزولة الخدمة الأمامية. الخدمة لا تنفّذ المزامنة بنفسها: وظيفتها
/// إبقاء عملية التطبيق حيّة بإشعار دائم ليواصل `StaffSyncEngine` (في المعزول
/// الرئيسي) النبضة والمزامنة كل 30 ث حتى والتطبيق في الخلفية.
@pragma('vm:entry-point')
void saloniKeepAliveCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp) async {}
  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();
}

class AndroidDeviceServices implements DeviceServices {
  bool _initialized = false;

  @override
  BootClock get bootClock => const PlatformBootClock();

  void _init() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'saloni_staff_sync',
        channelName: 'مزامنة الطابور',
        channelDescription: 'إشعار دائم يُبقي طابورك متزامنًا مع الصالون',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  @override
  Future<bool?> notificationsAllowed() async =>
      await FlutterForegroundTask.checkNotificationPermission() ==
      NotificationPermission.granted;

  @override
  Future<bool?> requestNotifications() async =>
      await FlutterForegroundTask.requestNotificationPermission() ==
      NotificationPermission.granted;

  @override
  Future<void> requestBatteryExemption() async {
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  @override
  Future<void> startKeepAlive({required String title, required String text}) async {
    _init();
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
          notificationTitle: title, notificationText: text);
      return;
    }
    await FlutterForegroundTask.startService(
      serviceId: 7301,
      notificationTitle: title,
      notificationText: text,
      callback: saloniKeepAliveCallback,
    );
  }

  @override
  Future<void> updateKeepAlive({required String title, required String text}) async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
          notificationTitle: title, notificationText: text);
    }
  }

  @override
  Future<void> stopKeepAlive() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}

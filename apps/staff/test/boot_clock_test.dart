import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_api/staff_sync.dart';
import 'package:saloni_staff/core/platform/boot_clock.dart';

/// ق40 (مراجعة F1): قراءة «منذ تشغيل الجهاز» عبر قناة `saloni/boot_clock`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('saloni/boot_clock');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('يقرأ الوقت منذ التشغيل وعدّاد التشغيل من أندرويد', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'read');
      return {'sinceBootMs': 5400000, 'bootId': '12'};
    });
    expect(await const PlatformBootClock().read(), const BootReading(Duration(minutes: 90), bootId: '12'));
  });

  test('بلا عدّاد تشغيل (أندرويد قديم)', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => {'sinceBootMs': 1000, 'bootId': null});
    expect(await const PlatformBootClock().read(), const BootReading(Duration(seconds: 1)));
  });

  test('قناة غير متاحة (iOS) أو خطأ ← null', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'x'));
    expect(await const PlatformBootClock().read(), isNull);
    messenger.setMockMethodCallHandler(channel, (call) async => {'junk': true});
    expect(await const PlatformBootClock().read(), isNull);
  });
}

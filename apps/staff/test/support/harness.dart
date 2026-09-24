import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_api/saloni_api.dart' as sa;
import 'package:saloni_staff/app.dart';
import 'package:saloni_staff/core/platform/device_services.dart';
import 'package:saloni_staff/core/platform/push.dart';
import 'package:saloni_staff/core/platform/storage.dart';
import 'package:saloni_staff/core/prefs.dart';
import 'package:saloni_staff/state/app_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_server.dart';

class Harness {
  Harness(this.server, this.services, this.container);
  final FakeServer server;
  final AppServices services;
  final ProviderContainer container;

  AuthController get auth => container.read(authProvider);
}

/// يشغّل التطبيق كاملًا (الموجّه، الأدوار، المستودع، المحرك) فوق سيرفر وهمي،
/// بعرض هاتف 360 منطقية واتجاه RTL.
Future<Harness> pumpStaffApp(
  WidgetTester tester,
  FakeServer server, {
  bool signedIn = true,
  double width = 360,
  double height = 800,
  double textScale = 1.0,
}) async {
  SharedPreferences.setMockInitialValues({
    'onboarding_barber': true,
    'onboarding_manager': true,
    'notifCheckDone': true,
  });
  final prefs = await AppPrefs.load();
  final tokens = sa.InMemoryTokenStore();
  if (signedIn) {
    await tokens.save(
      sa.Session(
        accessToken: 'access',
        refreshToken: 'refresh',
        role: sa.UserRole.fromWire(server.role),
        salonCode: 'RAHA-27',
      ),
      persist: true,
    );
  }
  final services = AppServices.build(
    baseUrl: 'http://test.local',
    inner: server.client(),
    storage: InMemoryStoragePlatform(tokenStore: tokens),
    device: const NoopDeviceServices(),
    push: NoopPushService(),
    prefs: prefs,
  );

  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = Size(width * 3, height * 3);
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [servicesProvider.overrideWithValue(services)],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          textScaler: TextScaler.linear(textScale),
        ),
        child: const StaffApp(),
      ),
    ),
  );
  await settle(tester);
  return Harness(server, services, container);
}

/// ينتظر اكتمال العمليات غير المتزامنة (طلبات السيرفر الوهمي) والإطارات.
Future<void> settle(WidgetTester tester, [int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

/// يفكك الشجرة ويوقف المؤقتات (المحرك، عداد الخدمة) قبل نهاية الاختبار.
Future<void> teardownApp(WidgetTester tester, Harness h) async {
  await tester.pumpWidget(const SizedBox());
  h.container.dispose();
  await tester.pump(const Duration(seconds: 1));
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:saloni_staff/features/barber/walkin_screen.dart';
import 'package:saloni_staff/state/app_services.dart';
import 'package:saloni_ui/saloni_ui.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

/// المرحلة 11 — ملاحظات التجربة الأولى على الهاتف.
void main() {
  String path(WidgetTester tester) => GoRouter.of(tester.element(find.byType(Scaffold).first))
      .routerDelegate
      .currentConfiguration
      .last
      .matchedLocation;

  Future<void> go(WidgetTester tester, String to) async {
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(to);
    await settle(tester);
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  group('1. زبون حاضر: اختيار الخدمات', () {
    testWidgets('تظهر خدمات الصالون، والخطأ يطابق ما على الشاشة، والمجموع يُحسب', (tester) async {
      final server = FakeServer();
      final h = await pumpStaffApp(tester, server);
      await tapKey(tester, 'walkin-button');

      expect(find.text('الخدمات'), findsOneWidget);
      expect(find.byType(ServiceChip), findsNWidgets(3));
      await tester.enterText(find.byType(TextField).at(0), 'عبدالعزيز');
      await tester.enterText(find.byType(TextField).at(1), '509876543');
      await tapKey(tester, 'walkin-submit');
      // لم تُختر خدمة: الرسالة تشير إلى قسم «الخدمات» الظاهر، ولا طلب للسيرفر.
      expect(find.text(walkInPickServiceError), findsOneWidget);
      expect(walkInPickServiceError, contains('«الخدمات»'));
      expect(server.walkInBodies, isEmpty);

      await tapKey(tester, 'walkin-service-s-hair');
      await tapKey(tester, 'walkin-service-s-beard');
      expect(find.text(walkInPickServiceError), findsNothing);
      expect(find.byKey(const Key('walkin-total')), findsOneWidget);
      expect(find.textContaining('45 د'), findsWidgets); // 30 + 15
      await tapKey(tester, 'walkin-submit');

      expect(server.walkInBodies.single['serviceIds'], ['s-hair', 's-beard']);
      expect(path(tester), '/b/queue');
      expect(find.text('عبدالعزيز'), findsWidgets);
      await teardownApp(tester, h);
    });

    testWidgets('خدمة واحدة في الصالون: تُختار تلقائيًا', (tester) async {
      final server = FakeServer();
      server.services
        ..clear()
        ..add({'id': 's-only', 'name': 'حلاقة', 'baseDurationMin': 20, 'priceCents': 3000, 'active': true});
      final h = await pumpStaffApp(tester, server);
      await tapKey(tester, 'walkin-button');

      expect(tester.widget<ServiceChip>(find.byType(ServiceChip)).selected, isTrue);
      await tester.enterText(find.byType(TextField).at(0), 'سالم');
      await tester.enterText(find.byType(TextField).at(1), '501112223');
      await tapKey(tester, 'walkin-submit');
      expect(server.walkInBodies.single['serviceIds'], ['s-only']);
      await teardownApp(tester, h);
    });

    testWidgets('لا خدمات: تنبيه واضح والإضافة معطلة', (tester) async {
      final server = FakeServer();
      server.services.clear();
      final h = await pumpStaffApp(tester, server);
      await tapKey(tester, 'walkin-button');

      expect(find.byKey(const Key('walkin-no-services')), findsOneWidget);
      expect(tester.widget<SaloniButton>(find.byKey(const Key('walkin-submit'))).onPressed, isNull);
      await teardownApp(tester, h);
    });
  });

  group('2. QR الصالون في الشريط العلوي', () {
    for (final role in ['barber', 'manager']) {
      testWidgets('يفتح رمز الصالون فورًا ($role)', (tester) async {
        final h = await pumpStaffApp(tester, FakeServer(role: role));
        expect(find.byKey(const Key('salon-qr')), findsOneWidget);
        await tester.tap(find.byKey(const Key('salon-qr')));
        await settle(tester);

        final qr = tester.widget<QrImageView>(find.byKey(const Key('salon-qr-image')));
        expect(qr, isNotNull);
        expect(find.text('RAHA-27'), findsOneWidget);
        expect(find.byKey(const Key('salon-qr-copy')), findsOneWidget);
        await teardownApp(tester, h);
      });
    }
  });

  group('3–4. «لن أعمل اليوم»: تأكيد، تغيّر فوري، تراجع، ومنع الاستراحة', () {
    testWidgets('الحلاق: تأكيد ثم تغيّر فوري، الاستراحة معطلة، ثم يتراجع بنفسه', (tester) async {
      final server = FakeServer();
      final h = await pumpStaffApp(tester, server);
      await go(tester, '/b/breaks');
      expect(tester.widget<SaloniButton>(find.byKey(const Key('emergency-break'))).onPressed, isNotNull);

      await tapKey(tester, 'absent-today');
      // تأكيد قبل التنفيذ — ولا شيء يُسجَّل قبل الموافقة.
      expect(find.byKey(const Key('absent-confirm')), findsOneWidget);
      expect(server.eventTypes, isNot(contains('absent_today')));
      await tapKey(tester, 'absent-confirm');

      expect(find.byKey(const Key('absent-banner')), findsOneWidget);
      expect(find.textContaining('سُجّل أنك لن تعمل اليوم'), findsOneWidget); // snackbar
      expect(server.eventTypes, contains('absent_today'));
      expect(tester.widget<SaloniButton>(find.byKey(const Key('emergency-break'))).onPressed, isNull);
      expect(find.textContaining('غير متاحة لأنك أبلغت أنك لن تعمل اليوم'), findsOneWidget);
      expect(find.textContaining('راجع مديرك'), findsNothing);

      await tapKey(tester, 'absent-undo');
      expect(find.textContaining('تبقى حيث هي'), findsOneWidget); // النقل لا يُعكس تلقائيًا
      await tester.tap(find.text('نعم، سأعمل اليوم'));
      await settle(tester);

      expect(server.eventTypes, contains('absent_cancelled'));
      expect(find.byKey(const Key('absent-banner')), findsNothing);
      expect(find.byKey(const Key('absent-today')), findsOneWidget);
      expect(tester.widget<SaloniButton>(find.byKey(const Key('emergency-break'))).onPressed, isNotNull);
      // بعد تحديث من السيرفر تبقى الحالة كما هي.
      await h.container.read(barberRepoProvider).refresh();
      await settle(tester);
      expect(find.byKey(const Key('absent-today')), findsOneWidget);
      await teardownApp(tester, h);
    });

    testWidgets('دون اتصال: الحالة تتغير فورًا ويُحفظ الحدث للإرسال لاحقًا', (tester) async {
      final server = FakeServer();
      final h = await pumpStaffApp(tester, server);
      await go(tester, '/b/breaks');
      server.online = false;
      await h.container.read(barberRepoProvider).refresh();
      await settle(tester);

      await tapKey(tester, 'absent-today');
      await tapKey(tester, 'absent-confirm');
      expect(find.byKey(const Key('absent-banner')), findsOneWidget);
      expect(find.textContaining('عند عودة الاتصال'), findsWidgets);
      expect(server.eventTypes, isNot(contains('absent_today')));

      server.online = true;
      await h.container.read(barberRepoProvider).refresh();
      await settle(tester);
      expect(server.eventTypes, contains('absent_today'));
      expect(find.byKey(const Key('absent-banner')), findsOneWidget);
      await teardownApp(tester, h);
    });

    testWidgets('غياب سجّله المدير: الحلاق لا يرى زر التراجع بل «تواصل مع مدير الصالون»', (tester) async {
      final server = FakeServer()
        ..absent = true
        ..absenceBySelf = false;
      final h = await pumpStaffApp(tester, server);
      await go(tester, '/b/breaks');
      expect(find.text('سجّل المدير أنك لن تعمل اليوم'), findsOneWidget);
      expect(find.byKey(const Key('absent-undo')), findsNothing);
      expect(find.textContaining('تواصل مع مدير الصالون'), findsOneWidget);
      expect(tester.widget<SaloniButton>(find.byKey(const Key('emergency-break'))).onPressed, isNull);
      await teardownApp(tester, h);
    });

    testWidgets('المدير يتراجع دائمًا عن غيابه — ولو سجّله غيره', (tester) async {
      final server = FakeServer(role: 'manager')
        ..absent = true
        ..absenceBySelf = false;
      final h = await pumpStaffApp(tester, server);
      await go(tester, '/b/breaks');
      expect(find.textContaining('راجع مديرك'), findsNothing);
      await tapKey(tester, 'absent-undo');
      await tester.tap(find.text('نعم، سأعمل اليوم'));
      await settle(tester);
      expect(server.eventTypes, contains('absent_cancelled'));
      expect(find.byKey(const Key('absent-today')), findsOneWidget);
      await teardownApp(tester, h);
    });

    testWidgets('المدير يلغي غياب حلاق من شاشة الطوابير', (tester) async {
      final server = FakeServer(role: 'manager');
      server.managerQueues = [server.queueBarber(id: 'b2', name: 'سعد', state: 'absent_today', accepting: false)];
      server.managerAbsences = [
        {'id': 'abs-1', 'staffId': 'b2', 'workDate': '2026-09-24', 'reason': null},
      ];
      final h = await pumpStaffApp(tester, server);
      await tapKey(tester, 'undo-absence-b2');
      expect(find.textContaining('تبقى حيث هي'), findsOneWidget);
      await tester.tap(find.text('إلغاء الغياب').last);
      await settle(tester);
      expect(server.deletedAbsenceIds, ['abs-1']);
      await teardownApp(tester, h);
    });
  });

  group('5. التنقل: رجوع واضح وزر رجوع أندرويد', () {
    testWidgets('المدير ← «طابوري»: رجوع ظاهر إلى لوحة المدير، وزر أندرويد يعيده', (tester) async {
      final h = await pumpStaffApp(tester, FakeServer(role: 'manager'));
      expect(path(tester), '/m/queues');
      await tester.tap(find.widgetWithText(SaloniButton, 'طابوري'));
      await settle(tester);
      expect(path(tester), '/b/queue');
      expect(find.byKey(const Key('shell-back')), findsOneWidget);
      expect(find.text('لوحة المدير'), findsOneWidget);
      // سهم الرجوع في RTL يشير إلى اليمين.
      final icon = tester.widget<SaloniIcon>(
          find.descendant(of: find.byKey(const Key('shell-back')), matching: find.byType(SaloniIcon)));
      expect(icon.name, SaloniIconName.caretRight);

      await tapKey(tester, 'shell-back');
      expect(path(tester), '/m/queues');

      // زر الرجوع في أندرويد: من «استراحاتي» إلى «طابوري» ثم إلى لوحة المدير.
      await go(tester, '/b/breaks');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(path(tester), '/b/queue');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(path(tester), '/m/queues');
      await teardownApp(tester, h);
    });

    testWidgets('الحلاق: لا رجوع إلى لوحة المدير، وأندرويد يعيد التبويبات إلى «طابوري»', (tester) async {
      final h = await pumpStaffApp(tester, FakeServer());
      expect(find.byKey(const Key('shell-back')), findsNothing);
      for (final tab in ['/b/payments', '/b/breaks', '/b/more']) {
        await go(tester, tab);
        await tester.binding.handlePopRoute();
        await settle(tester);
        expect(path(tester), '/b/queue', reason: tab);
      }
      await teardownApp(tester, h);
    });

    testWidgets('شاشة «زبون حاضر»: زر رجوع ظاهر ورجوع أندرويد يعيدان إلى «طابوري»', (tester) async {
      final h = await pumpStaffApp(tester, FakeServer());
      await tapKey(tester, 'walkin-button');
      expect(path(tester), '/b/walkin');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(path(tester), '/b/queue');

      await tapKey(tester, 'walkin-button');
      await tester.tap(find.bySemanticsLabel('رجوع'));
      await settle(tester);
      expect(path(tester), '/b/queue');

      // فُتحت مباشرة (دون مكدّس): الرجوع إلى «طابوري» لا إلى شاشة البداية.
      await go(tester, '/b/walkin');
      await tester.tap(find.bySemanticsLabel('رجوع'));
      await settle(tester);
      expect(path(tester), '/b/queue');
      await teardownApp(tester, h);
    });

    testWidgets('تبويبات المدير: أندرويد يعيد إلى «الطوابير»', (tester) async {
      final h = await pumpStaffApp(tester, FakeServer(role: 'manager'));
      for (final tab in ['/m/reports', '/m/salon']) {
        await go(tester, tab);
        await tester.binding.handlePopRoute();
        await settle(tester);
        expect(path(tester), '/m/queues', reason: tab);
      }
      await teardownApp(tester, h);
    });
  });
}

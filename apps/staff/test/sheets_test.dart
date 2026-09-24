import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_ui/saloni_ui.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

SaloniButton _button(WidgetTester tester, String key) =>
    tester.widget<SaloniButton>(find.byKey(Key(key)));

void main() {
  group('ورقة الزبون المتأخر (ق10، ق21)', () {
    testWidgets('قبل التأجيل: «لم يحضر» معطل، والتأجيل يرسل عدد الأدوار', (tester) async {
      final server = FakeServer()
        ..booking(id: 'b1', name: 'فهد القحطاني', status: 'called', position: 1)
        ..booking(id: 'b2', name: 'سلطان', position: 2)
        ..booking(id: 'b3', name: 'ريان', position: 3);
      final h = await pumpStaffApp(tester, server);

      await tester.tap(find.text('لم يصل بعد؟'));
      await settle(tester);
      expect(find.text('فهد لم يصل بعد'), findsOneWidget);
      expect(_button(tester, 'late-noshow').onPressed, isNull);
      expect(find.text('يُتاح بعد استخدام التأجيل'), findsOneWidget);

      await tester.tap(find.text('دوران'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('late-postpone')));
      await settle(tester);

      final e = server.events.singleWhere((e) => e['type'] == 'postponed');
      expect(e['bookingId'], 'b1');
      expect(e['payload'], {'steps': 2});
      // ق21: يُستدعى التالي فورًا (محليًا حتى تصل حالة السيرفر).
      expect(find.text('سلطان'), findsWidgets);
      await teardownApp(tester, h);
    });

    testWidgets('بعد التأجيل: لا تأجيل ثانٍ، و«لم يحضر» متاح', (tester) async {
      final server = FakeServer()
        ..booking(id: 'b1', name: 'فهد القحطاني', status: 'called', position: 1, postponementUsed: true);
      final h = await pumpStaffApp(tester, server);

      await tester.tap(find.text('لم يصل بعد؟'));
      await settle(tester);
      expect(find.byKey(const Key('late-postpone')), findsNothing);
      expect(_button(tester, 'late-noshow').onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('late-noshow')));
      await settle(tester);
      expect(server.eventTypes, contains('no_show'));
      expect(find.text('فهد القحطاني'), findsNothing);
      await teardownApp(tester, h);
    });

    testWidgets('«انتظاره قليلًا» يسجّل waited', (tester) async {
      final server = FakeServer()..booking(id: 'b1', name: 'فهد القحطاني', status: 'called', position: 1);
      final h = await pumpStaffApp(tester, server);
      await tester.tap(find.text('لم يصل بعد؟'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('late-wait')));
      await settle(tester);
      expect(server.eventTypes, contains('waited'));
      await teardownApp(tester, h);
    });
  });

  testWidgets('تعديل الخدمة: معاينة الأثر، تحذير الإغلاق، وقرار لكل متأثر (ق9، ق24)', (tester) async {
    final server = FakeServer()
      ..booking(id: 'b1', name: 'محمد العتيبي', status: 'in_service', startedMinAgo: 10, position: 0)
      ..booking(id: 'b2', name: 'عبدالله', position: 1)
      ..booking(id: 'b3', name: 'ريان', position: 2);
    final now = DateTime.now().toUtc();
    server.impact = {
      'bookingId': 'b1',
      'newDurationMin': 45,
      'newPriceCents': 6000,
      'changes': [
        {
          'bookingId': 'b2',
          'customerName': 'عبدالله',
          'before': now.add(const Duration(minutes: 20)).toIso8601String(),
          'after': now.add(const Duration(minutes: 55)).toIso8601String(),
          'deltaMin': 35,
          'pastClosing': false,
          'notify': true,
        },
        {
          'bookingId': 'b3',
          'customerName': 'ريان',
          'before': now.add(const Duration(minutes: 50)).toIso8601String(),
          'after': now.add(const Duration(minutes: 85)).toIso8601String(),
          'deltaMin': 35,
          'pastClosing': true,
          'notify': true,
        },
      ],
      'pastClosing': [
        {'bookingId': 'b3', 'customerName': 'ريان', 'end': now.add(const Duration(minutes: 115)).toIso8601String()},
      ],
    };
    final h = await pumpStaffApp(tester, server);

    await tester.tap(find.text('تعديل الخدمة'));
    await settle(tester);
    expect(find.text('تعديل خدمة محمد'), findsOneWidget);
    // التأكيد معطل حتى يتغيّر الاختيار.
    expect(_button(tester, 'confirm-edit').onPressed, isNull);

    await tester.tap(find.byKey(const Key('svc-s-both')));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);

    expect(server.requests, contains('POST /staff/impact'));
    expect(find.byKey(const Key('impact-list')), findsOneWidget);
    expect(find.text('بعد الإغلاق'), findsOneWidget);
    expect(find.text('تجاوز وقت الإغلاق'), findsOneWidget);

    // ريان: إلغاء مع إبلاغ.
    await tester.ensureVisible(find.text('إلغاء مع إبلاغ'));
    await tester.tap(find.text('إلغاء مع إبلاغ'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('confirm-edit')));
    await tester.tap(find.byKey(const Key('confirm-edit')));
    await settle(tester);

    final changed = server.events.singleWhere((e) => e['type'] == 'services_changed');
    expect(changed['payload'], {
      'serviceIds': ['s-hair', 's-both'],
    });
    final decision = server.events.singleWhere((e) => e['type'] == 'closing_decision');
    expect(decision['bookingId'], 'b3');
    expect((decision['payload'] as Map)['decision'], 'cancel');
    await teardownApp(tester, h);
  });

  testWidgets('تعديل الخدمة دون اتصال: لا معاينة، والتعديل يُقبل ويُحفظ', (tester) async {
    final server = FakeServer()
      ..booking(id: 'b1', name: 'محمد العتيبي', status: 'in_service', startedMinAgo: 10, position: 0);
    final h = await pumpStaffApp(tester, server);
    server.online = false;
    await tester.runAsync(() async {});
    // يسجّل الانقطاع عبر تحديث فاشل.
    await tester.drag(find.byType(ListView).first, const Offset(0, 300));
    await settle(tester);

    await tester.tap(find.text('تعديل الخدمة'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('svc-s-beard')));
    await settle(tester);
    expect(find.text('معاينة الأثر تحتاج اتصالًا'), findsOneWidget);
    expect(server.requests.where((r) => r == 'POST /staff/impact'), isEmpty);
    await tester.tap(find.byKey(const Key('confirm-edit')));
    await settle(tester);
    expect(find.textContaining('تهذيب لحية'), findsWidgets);
    await teardownApp(tester, h);
  });
}

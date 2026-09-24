import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_staff/state/app_services.dart';
import 'package:saloni_ui/saloni_ui.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

void main() {
  testWidgets('طابوري: يعرض الخدمة الجارية والتالين وشريط الاتصال', (tester) async {
    final server = FakeServer()
      ..booking(id: 'b1', name: 'محمد العتيبي', status: 'in_service', startedMinAgo: 10, position: 0, durationMin: 45)
      ..booking(id: 'b2', name: 'فهد القحطاني', status: 'called', position: 1)
      ..booking(id: 'b3', name: 'عبدالله', position: 2, walkIn: true);
    final h = await pumpStaffApp(tester, server);

    expect(find.text('طابوري'), findsWidgets);
    expect(find.byType(CurrentServiceCard), findsOneWidget);
    expect(find.text('محمد العتيبي'), findsOneWidget);
    expect(find.text('فهد القحطاني'), findsOneWidget);
    expect(find.text('عبدالله'), findsOneWidget);
    expect(find.text('التالون'), findsOneWidget);
    final bar = tester.widget<ConnectionBar>(find.byType(ConnectionBar));
    expect(bar.state, SaloniConnectionState.online);
    await teardownApp(tester, h);
  });

  testWidgets('إنهاء الخدمة وتأكيد الدفع يمران عبر صندوق الأحداث', (tester) async {
    final server = FakeServer()
      ..booking(id: 'b1', name: 'محمد العتيبي', status: 'in_service', startedMinAgo: 20, position: 0)
      ..booking(id: 'b2', name: 'فهد القحطاني', status: 'called', position: 1);
    final h = await pumpStaffApp(tester, server);

    await tester.tap(find.text('إنهاء الخدمة'));
    await settle(tester);
    // ورقة الدفع تظهر بعد الإنهاء مباشرة (دون انتظار الشبكة).
    expect(find.byKey(const Key('confirm-payment')), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-payment')));
    await settle(tester);

    expect(server.eventTypes, containsAllInOrder(['service_finished', 'payment_confirmed']));
    final finished = server.events.firstWhere((e) => e['type'] == 'service_finished');
    expect(finished['bookingId'], 'b1');
    expect(finished['deviceSeq'], isA<int>());
    expect(find.byType(CurrentServiceCard), findsNothing);
    await teardownApp(tester, h);
  });

  testWidgets('بدء خدمة التالي يسجّل service_started ويعرض بطاقة الخدمة', (tester) async {
    final server = FakeServer()..booking(id: 'b2', name: 'فهد القحطاني', status: 'called', position: 1);
    final h = await pumpStaffApp(tester, server);

    expect(find.byType(CurrentServiceCard), findsNothing);
    await tester.tap(find.byKey(const Key('start-next')));
    await settle(tester);

    expect(server.eventTypes, contains('service_started'));
    expect(find.byType(CurrentServiceCard), findsOneWidget);
    await teardownApp(tester, h);
  });

  testWidgets('دون اتصال: الإجراءات تُحفظ محليًا، وإضافة الحاضر معطلة بسبب واضح', (tester) async {
    final server = FakeServer()..booking(id: 'b2', name: 'فهد القحطاني', status: 'called', position: 1);
    final h = await pumpStaffApp(tester, server);

    server.online = false;
    await h.container.read(barberRepoProvider).refresh();
    await settle(tester);

    final bar = tester.widget<ConnectionBar>(find.byType(ConnectionBar));
    expect(bar.state, SaloniConnectionState.offline);
    final walkIn = tester.widget<SaloniButton>(find.byKey(const Key('walkin-button')));
    expect(walkIn.onPressed, isNull);
    expect(find.text('إضافة زبون حاضر تحتاج اتصالًا بالإنترنت.'), findsOneWidget);

    // البدء يعمل دون اتصال ويُحفظ في الصندوق.
    await tester.tap(find.byKey(const Key('start-next')));
    await settle(tester);
    expect(find.byType(CurrentServiceCard), findsOneWidget);
    expect(server.eventTypes, isNot(contains('service_started')));
    expect(h.container.read(barberRepoProvider).pending, 1);

    // عودة الاتصال: يُرسل الصندوق.
    server.online = true;
    server.requests.clear();
    await h.container.read(barberRepoProvider).refresh();
    await settle(tester);
    expect(server.requests.first, 'POST /sync/events');
    expect(server.eventTypes, contains('service_started'));
    await teardownApp(tester, h);
  });

  testWidgets('إضافة زبون حاضر متصلًا تضيفه لآخر الطابور', (tester) async {
    final server = FakeServer()..booking(id: 'b2', name: 'فهد القحطاني', status: 'called', position: 1);
    final h = await pumpStaffApp(tester, server);

    await tester.tap(find.byKey(const Key('walkin-button')));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(0), 'عبدالعزيز');
    await tester.enterText(find.byType(TextField).at(1), '509876543');
    await tester.tap(find.text('حلاقة شعر'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('walkin-submit')));
    await settle(tester);

    expect(server.requests, contains('POST /staff/walk-ins'));
    expect(find.text('عبدالعزيز'), findsOneWidget);
    await teardownApp(tester, h);
  });

  testWidgets(
      'حجوزات من يوم سابق أُغلق (ق24) تظهر في قسم منفصل أعلى الشاشة وتُنهى '
      'وتُدفع عبر الصندوق', (tester) async {
    final server = FakeServer()
      ..booking(id: 'b1', name: 'محمد العتيبي', status: 'called', position: 0)
      ..previousDayBooking(id: 'p1', name: 'سلطان القحطاني');
    final h = await pumpStaffApp(tester, server);

    // القسم يظهر قبل «التالون» وبقية الشاشة.
    expect(find.text('من يوم سابق'), findsOneWidget);
    expect(find.text('سلطان القحطاني'), findsOneWidget);
    expect(find.byKey(const Key('finish-previous-p1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('finish-previous-p1')));
    await settle(tester);

    // إنهاء الخدمة يسجّل الحدث ويعرض ورقة الدفع فورًا.
    expect(server.eventTypes, contains('service_finished'));
    expect(
        server.events.firstWhere((e) => e['type'] == 'service_finished')['bookingId'],
        'p1');
    expect(find.byKey(const Key('confirm-payment')), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-payment')));
    await settle(tester);

    expect(server.eventTypes, containsAllInOrder(['service_finished', 'payment_confirmed']));
    expect(
        server.events.firstWhere((e) => e['type'] == 'payment_confirmed')['bookingId'],
        'p1');

    // بعد الإنهاء والدفع: تظهر «تأكيد الدفع» فقط ما لم يُؤكَّد بعد، ثم يختفي
    // القسم كليًا بعد أن يزيله السيرفر من `unfinishedFromPreviousDay` (هنا:
    // لا يزال يعيده السيرفر الوهمي، لكن حالة الدفع أصبحت مؤكدة محليًا فلا
    // يظهر زر «تأكيد الدفع» بعد الآن).
    expect(find.byKey(const Key('confirm-payment-previous-p1')), findsNothing);
    await teardownApp(tester, h);
  });
}

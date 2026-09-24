import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:saloni_api/saloni_api.dart' as sa;
import 'package:saloni_staff/core/error_texts.dart';
import 'package:saloni_staff/features/common/about_screen.dart';
import 'package:saloni_staff/features/common/ui.dart';
import 'package:saloni_staff/features/manager/settings_screen.dart';
import 'package:saloni_ui/saloni_ui.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

/// المرحلة 11 — ملاحظات التجربة الأولى (الجولة 2): «عن التطبيق»، المدير الذي
/// يحلق هدفًا للنقل (ق25)، ورسائل أخطاء قابلة للتشخيص.
void main() {
  Future<void> go(WidgetTester tester, String to) async {
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(to);
    await settle(tester);
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  group('1. عن التطبيق', () {
    testWidgets('من «المزيد» (الحلاق): الاسم والإصدار وبيانات المطوّر', (tester) async {
      final h = await pumpStaffApp(tester, FakeServer());
      await go(tester, '/b/more');
      await tapKey(tester, 'open-about');

      expect(find.text('عن التطبيق'), findsWidgets);
      expect(find.text('صالوني — احجز دوري'), findsOneWidget);
      expect(find.text('0.1.0 (1)'), findsOneWidget);
      expect(find.text('شركة فينكس لتطوير الأنظمة والحلول البرمجية'), findsOneWidget);
      expect(find.text('برمجة م. عبدالرحمن أبوعون'), findsOneWidget);
      expect(find.text('هاتف: '), findsOneWidget);
      // الرقم معزول LTR داخل السطر العربي.
      final number = tester.widget<Text>(find.byKey(const Key('about-phone-number')));
      expect(number.data, '0598789755');
      expect(number.textDirection, TextDirection.ltr);
      expect(tester.takeException(), isNull);
      await teardownApp(tester, h);
    });

    testWidgets('من إعدادات المدير', (tester) async {
      final h = await pumpStaffApp(tester, FakeServer(role: 'manager'));
      await go(tester, '/m/settings');
      await tester.scrollUntilVisible(find.byKey(const Key('open-about')), 300,
          scrollable: find.descendant(of: find.byType(ManagerSettingsScreen), matching: find.byType(Scrollable)).first);
      await tester.drag(find.byKey(const Key('open-about')), const Offset(0, -250));
      await settle(tester);
      await tester.tap(find.byKey(const Key('open-about')));
      await settle(tester);
      expect(find.text('برمجة م. عبدالرحمن أبوعون'), findsOneWidget);
      await teardownApp(tester, h);
    });

    testWidgets('النقر على الرقم أو «اتصال» يفتح tel:0598789755؛ والفشل يعرض الرقم', (tester) async {
      final opened = <Uri>[];
      var result = true;
      await tester.pumpWidget(MaterialApp(
        theme: SaloniTheme.dark(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: AboutScreen(openUrl: (u) async {
            opened.add(u);
            return result;
          })),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('about-phone')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('about-call')));
      await tester.tap(find.byKey(const Key('about-call')));
      await tester.pumpAndSettle();
      expect(opened.map((u) => u.toString()), ['tel:0598789755', 'tel:0598789755']);

      result = false;
      await tester.tap(find.byKey(const Key('about-phone')));
      await tester.pump();
      expect(find.text('تعذّر فتح الاتصال — الرقم 0598789755'), findsOneWidget);
    });
  });

  group('2. المدير الذي يحلق هدفٌ للنقل (ق25)', () {
    testWidgets('مدير بلا دوام يظهر في ورقة النقل مع السبب، و«اعمل بدوام الصالون» يجعله هدفًا', (tester) async {
      final server = FakeServer(role: 'manager');
      server.managerStaff = [
        {'id': 'b1', 'name': 'خالد', 'role': 'barber', 'active': true},
        {'id': 'm1', 'name': 'أبو فهد', 'role': 'manager', 'active': true},
        {'id': 'old', 'name': 'موقوف', 'role': 'barber', 'active': false},
      ];
      server.managerQueues = [
        server.queueBarber(id: 'b1', name: 'خالد', queue: [server.bookingJson(id: 'q1', name: 'فهد', barberId: 'b1')]),
      ];
      server.managerSchedules = [
        for (var d = 0; d < 7; d++) {'staffId': null, 'weekday': d, 'opensAt': '10:00', 'closesAt': '23:00'},
        {'staffId': 'm1', 'weekday': 5, 'opensAt': '14:00', 'closesAt': '22:00'},
      ];
      // السيرفر: من له دوام اليوم يظهر في الطوابير.
      server.onSchedulePut = (b) {
        if (b['staffId'] == 'm1' && !server.managerQueues.any((q) => q['id'] == 'm1')) {
          server.managerQueues = [...server.managerQueues, server.queueBarber(id: 'm1', name: 'أبو فهد', role: 'manager')];
        }
      };
      final h = await pumpStaffApp(tester, server);
      // الطوابير تذكر من لا دوام له بدل أن يختفي.
      expect(find.byKey(const Key('idle-staff-note')), findsOneWidget);
      expect(find.textContaining('أبو فهد (مدير)'), findsOneWidget);
      expect(find.textContaining('موقوف'), findsNothing);

      await tapKey(tester, 'transfer-q1');
      expect(find.byKey(const Key('idle-m1')), findsOneWidget);
      expect(find.text('لا دوام له — دوام الصالون لا يسري على المديرين'), findsOneWidget);
      // غير متاح: النقر لا يختاره.
      await tester.tap(find.byKey(const Key('idle-m1')));
      await settle(tester);
      expect(server.transfers, isEmpty);

      await tapKey(tester, 'adopt-hours-m1');
      // نُسخ دوام الصالون للأيام الستة التي لا دوام خاص له فيها (لا يُغيَّر يومه الخاص).
      final puts = server.schedulesPut.where((b) => b['staffId'] == 'm1').toList();
      expect(puts, hasLength(6));
      expect(puts.map((b) => b['weekday']), isNot(contains(5)));
      expect(puts.first, containsPair('opensAt', '10:00'));
      expect(find.byKey(const Key('idle-m1')), findsNothing);

      await tester.tap(find.text('أبو فهد').last);
      await settle(tester);
      await tapKey(tester, 'transfer-confirm');
      expect(server.transfers.single, {'bookingId': 'q1', 'toBarberId': 'm1'});
      await teardownApp(tester, h);
    });

    testWidgets('«طابوري» للمدير بلا دوام: شرح + «اعمل بدوام الصالون»', (tester) async {
      final server = FakeServer(role: 'manager')..noShift = true;
      server.managerSchedules = [
        for (var d = 0; d < 7; d++) {'staffId': null, 'weekday': d, 'opensAt': '09:00', 'closesAt': '21:00'},
      ];
      server.onSchedulePut = (_) => server.noShift = false;
      final h = await pumpStaffApp(tester, server);
      await go(tester, '/b/queue');
      expect(find.byKey(const Key('manager-no-shift')), findsOneWidget);
      expect(find.textContaining('يسري على الحلاقين فقط'), findsOneWidget);

      await tapKey(tester, 'adopt-salon-hours');
      // `GET /auth/session` ← accountId = barber-1 في السيرفر الوهمي.
      expect(server.schedulesPut, hasLength(7));
      expect(server.schedulesPut.every((b) => b['staffId'] == 'barber-1'), isTrue);
      expect(find.byKey(const Key('manager-no-shift')), findsNothing);
      await teardownApp(tester, h);
    });

    testWidgets('الحلاق بلا دوام: الرسالة القديمة بلا زر', (tester) async {
      final server = FakeServer()..noShift = true;
      final h = await pumpStaffApp(tester, server);
      expect(find.text('لا دوام لك اليوم'), findsOneWidget);
      expect(find.byKey(const Key('adopt-salon-hours')), findsNothing);
      await teardownApp(tester, h);
    });
  });

  group('3. رسائل الأخطاء', () {
    test('خطأ سيرفر غير متوقع: رمز S- من آخر 6 محارف لمعرّف الطلب', () {
      const e = sa.ApiError(
        code: 'INTERNAL',
        message: 'حدث خطأ غير متوقع',
        statusCode: 500,
        requestId: '0f9c2a1e-7b7d-4c55-9e33-a1b2c3d4e5f6',
      );
      expect(errorText(e), 'حدث خطأ غير متوقع في السيرفر (رمز: S-d4e5f6)');
    });

    test('خطأ داخل التطبيق: رمز C- بنوعه (لا يُبتلع)', () {
      Object? caught;
      try {
        (null as dynamic).length;
      } catch (e) {
        caught = e;
      }
      expect(errorText(caught!), startsWith('حدث خطأ غير متوقع في التطبيق (رمز: C-'));
      expect(errorText(const FormatException('x')), contains('C-FormatException'));
    });

    test('قاعدة الجهاز المحلية: رسالة الحفظ على الهاتف', () {
      final e = ArgumentError("Failed to load dynamic library 'libsqlite3.so'");
      expect(ErrorTexts.isLocalStoreError(e), isTrue);
      expect(errorText(e), contains('تعذّر الحفظ في ذاكرة الهاتف'));
    });

    test('أخطاء التحقق تذكر الحقل والمشكلة', () {
      const e = sa.ApiError(code: 'VALIDATION_FAILED', message: 'البيانات المدخلة غير صحيحة', statusCode: 400, details: [
        {'path': 'owner.username', 'code': 'invalid_username'},
        {'path': 'socialLinks.0.url', 'code': 'invalid_format'},
      ]);
      final t = errorText(e);
      expect(t, startsWith('البيانات غير صحيحة — اسم المستخدم: يبدأ بحرف لاتيني أو رقم'));
      expect(t, contains('رابط التواصل: صيغته غير صحيحة'));
      const wa = sa.ApiError(code: 'VALIDATION_FAILED', message: 'x', details: [
        {'path': 'whatsapp', 'code': 'invalid_international_phone'},
      ]);
      expect(errorText(wa), contains('رقم واتساب: يلزم رقم دولي كامل'));
    });

    test('الشبكة: لا إنترنت / السيرفر لا يُصل / المهلة / الوسيط 502', () {
      expect(errorText(sa.ApiError.network('SocketException: Failed host lookup: x')), startsWith('لا اتصال بالإنترنت'));
      expect(errorText(sa.ApiError.network('ClientException: Connection refused')), startsWith('تعذّر الوصول للسيرفر'));
      expect(errorText(sa.ApiError.timeout()), startsWith('انتهت مهلة الاتصال'));
      expect(errorText(const sa.ApiError(code: 'HTTP_502', message: 'x', statusCode: 502)),
          'السيرفر لا يستجيب حاليًا — حاول بعد قليل (رمز: HTTP-502)');
    });

    test('كل رمز معروف له نص عربي؛ والمجهول العام يُذكر رمزه', () {
      expect(errorText(const sa.ApiError(code: 'BARBER_NOT_WORKING', message: 'x', statusCode: 409)),
          contains('لا دوام لهذا الحلاق اليوم'));
      expect(errorText(const sa.ApiError(code: 'WEAK_PASSWORD', message: 'كلمة المرور يجب ألا تقل عن 10 أحرف')),
          'كلمة المرور يجب ألا تقل عن 10 أحرف');
      expect(errorText(const sa.ApiError(code: 'NEW_CODE', message: 'حدث خطأ غير متوقع', statusCode: 409)),
          'حدث خطأ غير متوقع (رمز: NEW_CODE)');
    });
  });

  group('4. التسجيل', () {
    testWidgets('اسم مستخدم يبدأ بـ«_» يُرفض محليًا كما يرفضه السيرفر', (tester) async {
      final server = FakeServer();
      final h = await pumpStaffApp(tester, server, signedIn: false);
      await go(tester, '/signup');
      await tester.enterText(find.byType(TextField).at(0), 'المالك');
      await tester.enterText(find.byType(TextField).at(1), '_owner');
      await tester.enterText(find.byType(TextField).at(2), 'long-enough-pass');
      await tester.enterText(find.byType(TextField).at(3), 'long-enough-pass');
      await tester.ensureVisible(find.text('التالي'));
      await tester.tap(find.text('التالي'));
      await settle(tester);
      expect(find.textContaining('ويبدأ بحرف أو رقم'), findsOneWidget);
      expect(server.registered, isNull);
      await teardownApp(tester, h);
    });
  });
}

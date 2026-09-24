// End-to-end (phase 11 trial feedback): every staff-app call made through the
// REAL Dart ApiClient against the REAL server (see run.sh), with the bodies the
// staff app actually sends — so a response the app cannot parse (a cast or a
// model mismatch — «حدث خطأ غير متوقع» on the phone) or a server 500 fails here
// with the name of the step.
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:saloni_api/saloni_api.dart';
import 'package:saloni_api/staff_sync.dart';
import 'package:test/test.dart';

final baseUrl = Platform.environment['E2E_BASE_URL'] ?? 'http://127.0.0.1:3790';
final serverDir =
    Platform.environment['E2E_SERVER_DIR'] ?? '${Directory.current.parent.path}/server';

void log(String step) => print('[e2e-contract] $step');

ApiClient newClient() => ApiClient(baseUrl: baseUrl, tokenStore: InMemoryTokenStore());

/// A valid 1×1 PNG (the server re-encodes uploads with sharp).
final pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

/// Runs one step; any failure names it (and keeps the original error/stack).
Future<T> step<T>(String name, Future<T> Function() run) async {
  try {
    final v = await run();
    log('ok  $name');
    return v;
  } catch (e, st) {
    log('FAIL $name: ${e.runtimeType}: $e');
    Error.throwWithStackTrace(TestFailure('step "$name" failed: ${e.runtimeType}: $e'), st);
  }
}

Future<void> vendorActivate(String code) async {
  final r = await Process.run('npx', ['ts-node', '--transpile-only', 'src/cli/vendor.ts', 'activate', code],
      workingDirectory: serverDir, runInShell: true);
  if (r.exitCode != 0) throw StateError('vendor activate failed: ${r.stdout}\n${r.stderr}');
}

void main() {
  test('staff app ↔ server contract: signup (ILS, Asia/Hebron), manager screens, barber, manager-as-barber transfer',
      () async {
    final suffix = List.generate(6, (_) => Random().nextInt(10)).join();
    const pw = 'e2e-Staff-Passw0rd';
    final manager = newClient();

    // ---- التسجيل كما يرسله التطبيق (فلسطين — الضفة، شيكل، هاتف بأرقام مشرقية) ----
    final reg = await step('registerSalon ILS/Asia/Hebron', () => manager.registerSalon(
          salon: {
            'name': 'صالون الخليل $suffix',
            'timezone': 'Asia/Hebron',
            'currency': 'ILS',
            'phone': '٠٥٩٩١٢٣٤٥٦',
            'address': 'الخليل — شارع السلام',
            'about': 'حلاقة رجالية',
          },
          owner: {'name': 'المالك', 'username': 'hebron$suffix', 'password': pw},
        ));
    expect(reg.salon.currency, 'ILS');
    expect(reg.session.salon.timezone, 'Asia/Hebron');
    final code = reg.salon.code;

    // «ساعات العمل» كما في التسجيل: دوام الصالون الافتراضي لكل يوم (يغطي الآن).
    for (var weekday = 0; weekday < 7; weekday++) {
      await step('putManagerSchedule salon default $weekday',
          () => manager.putManagerSchedule(weekday: weekday, opensAt: '00:00', closesAt: '23:59'));
    }
    final cut = await step('createManagerService ILS price', () async => Service.fromJson(
        await manager.createManagerService({'name': 'قص', 'durationMinutes': 30, 'price': 3500})));
    expect(cut.priceCents, 3500);
    final spare = await step('createManagerService 2',
        () => manager.createManagerService({'name': 'صبغة', 'durationMinutes': 45, 'price': 8000}));
    await step('getManagerServices', () async =>
        (await manager.getManagerServices()).map((j) => Service.fromJson(j as Map<String, dynamic>)).toList());
    await step('updateManagerService', () => manager.updateManagerService(spare['id'] as String, {'price': 9000, 'active': false}));
    await step('deleteManagerService', () => manager.deleteManagerService(spare['id'] as String));
    await step('getSessionInfo', () => manager.getSessionInfo());

    await vendorActivate(code);
    log('activated $code');

    // ---- ملف الصالون: واتساب دولي حر (ق41) + أخطاء التحقق بالتفصيل ----
    await step('getManagerProfile', () => manager.getManagerProfile());
    final saved = await step('updateManagerProfile whatsapp +970', () => manager.updateManagerProfile({
          'name': 'صالون الخليل $suffix',
          'about': null,
          'address': 'الخليل',
          'phone': '0599123456',
          'whatsapp': '00970599123456',
          'socialLinks': [
            {'platform': 'instagram', 'url': 'https://instagram.com/saloni'}
          ],
        }));
    expect(saved['whatsapp'], '+970599123456');
    await expectLater(
      manager.updateManagerProfile({'whatsapp': '0599123456'}),
      throwsA(isA<ApiError>()
          .having((e) => e.code, 'code', 'VALIDATION_FAILED')
          .having((e) => e.validationIssues.single.path, 'path', 'whatsapp')
          .having((e) => e.validationIssues.single.code, 'issue', 'invalid_international_phone')),
    );
    final photo = await step('uploadManagerPhoto',
        () => manager.uploadManagerPhoto(bytes: pngBytes, filename: 'a.png', contentType: 'image/png'));
    await step('deleteManagerPhoto', () => manager.deleteManagerPhoto(photo.id));
    await step('uploadManagerLogo',
        () => manager.uploadManagerLogo(bytes: pngBytes, filename: 'logo.png', contentType: 'image/png'));
    await step('deleteManagerLogo', () => manager.deleteManagerLogo());

    // ---- الكتالوج (بجسم شاشة التطبيق) ----
    final item = await step('createManagerCatalogItem service', () => manager.createManagerCatalogItem({
          'kind': 'service',
          'name': 'قص مميز',
          'description': null,
          'features': ['غسيل', 'تصفيف'],
          'price': 3500,
          'visible': true,
          'serviceId': cut.id,
        }));
    final product = await step('createManagerCatalogItem product', () => manager.createManagerCatalogItem({
          'kind': 'product',
          'name': 'زيت لحية',
          'description': 'زيت طبيعي',
          'features': <String>[],
          'price': null,
          'visible': true,
        }));
    await step('updateManagerCatalogItem', () => manager.updateManagerCatalogItem(item['id'] as String, {
          'name': 'قص مميز',
          'description': 'مع غسيل',
          'features': ['غسيل'],
          'price': 4000,
          'visible': false,
        }));
    await step('uploadManagerCatalogPhoto', () => manager.uploadManagerCatalogPhoto(item['id'] as String,
        bytes: pngBytes, filename: 'c.png', contentType: 'image/png'));
    await step('deleteManagerCatalogPhoto', () => manager.deleteManagerCatalogPhoto(item['id'] as String));
    await step('getManagerCatalog', () => manager.getManagerCatalog());
    await step('deleteManagerCatalogItem', () => manager.deleteManagerCatalogItem(product['id'] as String));

    // ---- الطاقم ----
    final barber = await step('createManagerStaff barber', () => manager.createManagerStaff(
        {'name': 'خالد', 'username': 'khaled$suffix', 'password': pw, 'role': 'barber'}));
    final barberId = barber['id'] as String;
    await step('updateManagerStaff', () => manager.updateManagerStaff(barberId, {'callAheadMinutes': 10}));
    await step('resetStaffCode', () => manager.resetStaffCode(barberId));
    final staff = await step('getManagerStaff', () => manager.getManagerStaff());
    final managerId = (staff.cast<Map>().firstWhere((s) => s['role'] == 'manager'))['id'] as String;
    // resetStaffCode revoked the barber's sessions — sign in afterwards.
    final barberApi = newClient();
    await step('loginStaff barber', () => barberApi.loginStaff(salonCode: code, username: 'khaled$suffix', password: pw));

    // ---- الدوام: المدير يحلق أيضًا — دوام خاص له (الافتراضي للحلاقين فقط) ----
    for (var weekday = 0; weekday < 7; weekday++) {
      await step('putManagerSchedule manager $weekday', () => manager.putManagerSchedule(
          staffId: managerId, weekday: weekday, opensAt: '00:00', closesAt: '23:59'));
    }
    await step('getManagerSchedules', () => manager.getManagerSchedules());

    // ---- الاستراحات والإجازات (بأجسام شاشة الدوام) ----
    final today = await step('getStaffToday barber', () => barberApi.getStaffToday());
    expect(today.day, isNotNull);
    final workDate = today.day!.workDate;
    final daily = await step('createManagerBreak daily all', () => manager.createManagerBreak(
        {'staffId': 'all', 'type': 'rest', 'startTime': '03:00', 'endTime': '03:15'}));
    expect(daily, hasLength(2), reason: 'all = barber + manager');
    final start = DateTime.now().toUtc().add(const Duration(hours: 2));
    final dated = await step('createManagerBreak dated prayer', () => manager.createManagerBreak({
          'staffId': barberId,
          'type': 'prayer',
          'workDate': workDate,
          'startsAt': start.toIso8601String(),
          'endsAt': start.add(const Duration(minutes: 15)).toIso8601String(),
        }));
    await step('createManagerBreak walk_in_only', () => manager.createManagerBreak(
        {'staffId': barberId, 'type': 'walk_in_only', 'startTime': '04:00', 'endTime': '04:30'}));
    await step('getManagerBreaks', () => manager.getManagerBreaks());
    await step('deleteManagerBreak', () => manager.deleteManagerBreak((dated.first as Map)['id'] as String));
    final tomorrow = DateTime.parse(workDate).add(const Duration(days: 1));
    final tomorrowStr =
        '${tomorrow.year.toString().padLeft(4, '0')}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
    final absence = await step('createManagerAbsence (reason null)',
        () => manager.createManagerAbsence({'staffId': barberId, 'workDate': tomorrowStr, 'reason': null}));
    await step('getManagerAbsences', () => manager.getManagerAbsences());
    await step('deleteManagerAbsence', () => manager.deleteManagerAbsence(absence['id'] as String));

    // ---- الإعدادات ----
    await step('getManagerSettings', () => manager.getManagerSettings());
    await step('updateManagerSettings', () => manager.updateManagerSettings({'maxActiveBookingsPerCustomer': 2}));
    await expectLater(
      manager.updateManagerSettings({'overrunAlertPercent': 10}),
      throwsA(isA<ApiError>().having((e) => e.validationIssues.single.path, 'path', 'overrunAlertPercent')),
    );

    // ---- الحلاق: نبضة، زبون حاضر، الأثر، الدفعات، «لن أعمل اليوم» والتراجع، الاستراحة ----
    final engine = StaffSyncEngine(api: barberApi, store: InMemoryLocalStore(), heartbeatInterval: const Duration(hours: 1));
    await engine.start();
    await engine.sync();
    expect(engine.state.status, ConnectionStatus.online);
    final walkIn = await step('createWalkIn barber',
        () => engine.createWalkIn(name: 'زبون حاضر', phone: '0599000111', serviceIds: [cut.id]));
    await step('getStaffImpact', () => barberApi.getStaffImpact(bookingId: walkIn.id, serviceIds: [cut.id]));
    await step('getStaffPayments', () => barberApi.getStaffPayments());
    for (final type in [DeviceEventType.breakStarted, DeviceEventType.breakEnded]) {
      await engine.recordEvent(type, payload: {'kind': 'rest'});
    }
    await engine.recordEvent(DeviceEventType.absentToday, payload: {'reason': 'مريض'});
    await engine.recordEvent(DeviceEventType.absentCancelled);
    final flushed = await step('flush break + absence + undo', () => engine.flushNow());
    expect(flushed.outcomes.map((o) => o.result), everyElement(SyncEventResult.applied),
        reason: flushed.outcomes.map((o) => '${o.result} ${o.reason}').join(', '));
    await step('getStaffToday after undo', () => barberApi.getStaffToday());

    // ---- المدير يحلق: طابوره، زبون حاضر عنده، والنقل إليه (ق25) ----
    final managerToday = await step('getStaffToday manager', () => manager.getStaffToday());
    expect(managerToday.day, isNotNull, reason: 'a manager with his own schedule has a queue');
    await step('heartbeat manager', () => manager.heartbeat(deviceSeq: 1));
    final queues = await step('getManagerQueues', () => manager.getManagerQueues());
    expect(queues.barbers.map((b) => b.id), containsAll([barberId, managerId]));
    final moved = await step('transferBooking barber → manager',
        () => manager.transferBooking(bookingId: walkIn.id, toBarberId: managerId));
    expect(moved.barberId, managerId);
    await step('transferBooking manager → barber',
        () => manager.transferBooking(bookingId: walkIn.id, toBarberId: barberId));
    await step('createWalkIn manager', () => manager.createWalkIn(name: 'حاضر للمدير', phone: '0599000222', serviceIds: [cut.id]));

    // ---- الزبائن والنزاعات والمستردة والتقارير ----
    for (final s in ['pending', 'active', 'suspended']) {
      await step('getManagerCustomers $s', () => manager.getManagerCustomers(status: s));
    }
    await step('getPhoneDisputes', () => manager.getPhoneDisputes());
    await step('getRecoveredEvents', () => manager.getRecoveredEvents(all: true));
    final day = DateTime.parse(workDate);
    final report = await step('getManagerReports', () => manager.getManagerReports(from: day, to: day));
    final perBarber = ((report['revenue'] as Map)['perBarber'] as List).cast<Map>();
    expect(perBarber.map((r) => r['staffId']), contains(managerId),
        reason: 'a manager with a schedule is listed per barber');

    await engine.dispose();
    await barberApi.logout();
    await manager.logout();
    log('PASS');
  });
}

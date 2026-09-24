// End-to-end: real server (see run.sh) + real ApiClient + real StaffSyncEngine.
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:saloni_api/saloni_api.dart';
import 'package:saloni_api/staff_sync.dart';
import 'package:test/test.dart';

final baseUrl = Platform.environment['E2E_BASE_URL'] ?? 'http://127.0.0.1:3790';
final serverDir = Platform.environment['E2E_SERVER_DIR'] ??
    '${Directory.current.parent.path}/server';

/// An HTTP client whose network can be switched off — simulates the barber's
/// phone losing connectivity (a transport error, exactly like airplane mode).
class SwitchableClient extends http.BaseClient {
  SwitchableClient() : _inner = http.Client();
  final http.Client _inner;
  bool offline = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (offline) {
      throw SocketException('e2e: network switched off', osError: const OSError('ENETUNREACH', 101));
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

void log(String step) => print('[e2e] $step');

ApiClient newClient([http.Client? httpClient]) => ApiClient(
      baseUrl: baseUrl,
      tokenStore: InMemoryTokenStore(),
      httpClient: httpClient,
    );

/// Salon-local time is kept near midday whatever the UTC hour, so the whole
/// flow always runs inside the 06:00–22:00 shift: `Etc/GMT-N` = UTC+N.
String middayTimezone(DateTime nowUtc) {
  final offset = 12 - nowUtc.hour; // -11 … +12
  if (offset == 0) return 'Etc/GMT';
  return offset > 0 ? 'Etc/GMT-$offset' : 'Etc/GMT+${-offset}';
}

Future<void> vendorActivate(String code) async {
  final r = await Process.run(
    'npx',
    ['ts-node', '--transpile-only', 'src/cli/vendor.ts', 'activate', code],
    workingDirectory: serverDir,
    runInShell: true,
  );
  if (r.exitCode != 0) {
    throw StateError('vendor activate failed (${r.exitCode}): ${r.stdout}\n${r.stderr}');
  }
  log('vendor CLI: ${(r.stdout as String).trim()}');
}

Future<T> eventually<T>(Future<T?> Function() probe, {String what = 'condition'}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (true) {
    final v = await probe();
    if (v != null) return v;
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
}

void main() {
  test('owner → vendor → manager → customers → barber offline sync → payment → history → report',
      () async {
    final rnd = Random();
    final suffix = List.generate(6, (_) => rnd.nextInt(10)).join();
    final tz = middayTimezone(DateTime.now().toUtc());
    const staffPassword = 'e2e-Staff-Passw0rd';
    const customerPassword = 'e2e-Cust-Pass';

    // 1. Owner self-registers the salon (ق37) → pending_activation + manager session.
    final manager = newClient();
    final reg = await manager.registerSalon(
      salon: {'name': 'صالون الاختبار $suffix', 'timezone': tz, 'currency': 'SAR'},
      owner: {'name': 'المالك', 'username': 'owner$suffix', 'password': staffPassword},
    );
    final code = reg.salon.code;
    expect(reg.salon.pendingActivation, isTrue);
    expect(reg.session.role, UserRole.manager);
    expect(reg.session.salon.timezone, tz);
    log('salon registered: $code ($tz), status ${reg.salon.status}');

    // The public profile is hidden until activation.
    await expectLater(newClient().getSalonProfile(code),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', 'SALON_NOT_FOUND')));

    // 2. Vendor activates it from the CLI.
    await vendorActivate(code);
    await eventually(() async => (await manager.getSessionInfo()).salon.isActive ? true : null,
        what: 'salon active');

    // 3. Manager: services, two barbers, salon-wide hours, approval required.
    final cut = Service.fromJson(await manager.createManagerService(
        {'name': 'قص شعر', 'durationMinutes': 30, 'price': 5000}));
    final beard = Service.fromJson(await manager.createManagerService(
        {'name': 'تهذيب لحية', 'durationMinutes': 15, 'price': 2500}));
    expect(cut.baseDurationMin, 30);
    expect(beard.priceCents, 2500);
    final barberA = await manager.createManagerStaff({
      'name': 'خالد', 'username': 'khaled$suffix', 'password': staffPassword, 'role': 'barber',
    });
    final barberB = await manager.createManagerStaff({
      'name': 'فهد', 'username': 'fahad$suffix', 'password': staffPassword, 'role': 'barber',
    });
    for (var weekday = 0; weekday < 7; weekday++) {
      await manager.putManagerSchedule(weekday: weekday, opensAt: '06:00', closesAt: '22:00');
    }
    await manager.updateManagerSettings({'requireAccountApproval': true});
    log('manager: 2 services, barbers ${barberA['name']} & ${barberB['name']}, hours 06:00–22:00 daily');

    final profile = await newClient().getSalonProfile(code);
    expect(profile.services.map((s) => s.name), containsAll(['قص شعر', 'تهذيب لحية']));
    expect(profile.hours, hasLength(7));
    expect(profile.openNow, isTrue);
    log('public profile: ${profile.name}, open now, ${profile.services.length} services');

    // 4. Barbers sign in on their phones; StaffSyncEngine heartbeats mark them connected.
    final netA = SwitchableClient();
    final apiA = newClient(netA);
    await apiA.loginStaff(salonCode: code, username: 'khaled$suffix', password: staffPassword);
    final changesA = <SyncChange>[];
    final storeA = InMemoryLocalStore();
    final engineA = StaffSyncEngine(api: apiA, store: storeA, onChanges: changesA.addAll,
        heartbeatInterval: const Duration(hours: 1));
    await engineA.start();
    await engineA.sync();
    expect(engineA.state.status, ConnectionStatus.online);
    expect(engineA.lastHeartbeat!.state, 'connected');

    final apiB = newClient();
    await apiB.loginStaff(salonCode: code, username: 'fahad$suffix', password: staffPassword);
    final engineB = StaffSyncEngine(api: apiB, store: InMemoryLocalStore(),
        heartbeatInterval: const Duration(hours: 1));
    await engineB.start();
    await engineB.sync();
    log('barbers online (heartbeat state=${engineA.lastHeartbeat!.state})');

    // 5. Customer 1 registers → pending (ACCOUNT_PENDING) → manager approves.
    final c1 = newClient();
    final s1 = await c1.registerCustomer(
        salonCode: code, name: 'سالم', phone: '05${suffix}11', password: customerPassword);
    expect(s1.account!.status, 'pending');
    expect((await c1.getCustomerToday()).accountPending, isTrue);
    await expectLater(
      c1.getQuote(serviceIds: [cut.id], barberId: barberA['id'] as String, kind: BookingKind.queue),
      throwsA(isA<ApiError>().having((e) => e.isAccountPending, 'ACCOUNT_PENDING', isTrue)),
    );
    await manager.approveCustomer(s1.account!.id);
    log('customer 1 registered (pending → ACCOUNT_PENDING on quote) → approved');

    // 6. Customer 1 books barber A.
    final today = await c1.getCustomerToday();
    expect(today.accountPending, isFalse);
    final a = today.barbers.firstWhere((b) => b.id == barberA['id']);
    expect(a.accepting, isTrue);
    expect(a.dayState, BarberDayState.connected);
    final quote = await c1.getQuote(serviceIds: [cut.id], barberId: a.id, kind: BookingKind.queue);
    expect(quote.outcome, QuoteOutcome.accept);
    expect(quote.priceCents, 5000);
    final booking1 = await c1.createBooking(serviceIds: [cut.id], barberId: a.id, kind: BookingKind.queue);
    expect(booking1.customerName, 'سالم');
    expect(booking1.services.single.name, 'قص شعر');
    final current1 = (await c1.getCurrentBooking())!;
    expect(current1.booking.id, booking1.id);
    expect(current1.barber!.name, 'خالد');
    await c1.markBookingSeen(booking1.id, current1.eta);
    log('customer 1 booked ${booking1.id.substring(0, 8)} with خالد, ETA ${current1.eta.toIso8601String()}');

    // 7. Customer 2 books barber A too; the manager transfers it to barber B (ق25).
    final c2 = newClient();
    final s2 = await c2.registerCustomer(
        salonCode: code, name: 'نواف', phone: '05${suffix}22', password: customerPassword);
    await manager.approveCustomer(s2.account!.id);
    final booking2 = await c2.createBooking(serviceIds: [cut.id, beard.id], barberId: a.id, kind: BookingKind.queue);
    expect(booking2.priceCents, 7500);
    final queues = await manager.getManagerQueues();
    final qa = queues.barbers.firstWhere((b) => b.id == a.id);
    expect(qa.queue.map((b) => b.id), containsAll([booking1.id, booking2.id]));
    expect(qa.queue.every((b) => b.customerPhone != null), isTrue);
    final moved = await manager.transferBooking(bookingId: booking2.id, toBarberId: barberB['id'] as String);
    expect(moved.barberId, barberB['id']);
    final current2 = (await c2.getCurrentBooking())!;
    expect(current2.barber!.name, 'فهد');
    expect(current2.lastChangeReasonCode, 'transferred');
    final todayB = await apiB.getStaffToday();
    expect(todayB.queue.map((b) => b.id), contains(booking2.id));
    // Barber A's engine sees the removal in the change feed.
    await engineA.sync();
    expect(changesA.where((c) => c.bookingId == booking2.id).map((c) => c.type), contains('booking_removed'));
    log('customer 2 booked with خالد → transferred to فهد (reason ${current2.lastChangeReasonCode})');

    // 8. Barber A starts and finishes customer 1 OFFLINE, then syncs.
    final staffToday = await apiA.getStaffToday();
    expect(staffToday.day, isNotNull);
    final mine = staffToday.queue.firstWhere((b) => b.id == booking1.id);
    expect(mine.customerPhone, isNotNull);
    expect(mine.status, anyOf(BookingStatus.waiting, BookingStatus.called));
    netA.offline = true;
    await engineA.sync();
    expect(engineA.state.status, ConnectionStatus.offline);
    final offlineSince = engineA.state.since;
    await expectLater(engineA.createWalkIn(name: 'حاضر', phone: '0500000000', serviceIds: [cut.id]),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', 'OFFLINE_WALK_IN_REFUSED')));
    final started = await engineA.recordEvent(DeviceEventType.serviceStarted, bookingId: booking1.id);
    await Future<void>.delayed(const Duration(seconds: 2));
    final finished = await engineA.recordEvent(DeviceEventType.serviceFinished, bookingId: booking1.id);
    await engineA.sync(); // still offline: nothing leaves the phone
    expect(engineA.state.status, ConnectionStatus.offline);
    expect(engineA.state.since, offlineSince, reason: 'offline since stays stable');
    expect(engineA.state.pendingCount, 2);
    expect(finished.deviceSeq, started.deviceSeq + 1);
    log('barber offline: recorded service_started + service_finished (pending ${engineA.state.pendingCount})');

    netA.offline = false;
    final flushed = await engineA.flushNow();
    expect(flushed.outcomes.map((o) => o.result), everyElement(SyncEventResult.applied),
        reason: flushed.outcomes.map((o) => '${o.eventId}: ${o.result} ${o.reason}').join('\n'));
    expect(flushed.sent, 2);
    expect(engineA.state.status, ConnectionStatus.online);
    expect(engineA.state.pendingCount, 0);
    log('back online: flushNow → ${flushed.outcomes.map((o) => o.result.name).join(', ')}');

    // 9. Payment confirmed from the device.
    final payments = await apiA.getStaffPayments();
    final pay = payments.firstWhere((p) => p.bookingId == booking1.id);
    expect(pay.status, PaymentStatus.awaitingConfirmation);
    expect(pay.amountCents, 5000);
    expect(pay.customerName, 'سالم');
    await engineA.recordEvent(DeviceEventType.paymentConfirmed,
        bookingId: booking1.id, payload: {'amount': pay.amountCents});
    final paid = await engineA.flushNow();
    expect(paid.outcomes.single.result, SyncEventResult.applied);
    final confirmed = (await apiA.getStaffPayments()).firstWhere((p) => p.bookingId == booking1.id);
    expect(confirmed.status, PaymentStatus.confirmed);
    log('payment confirmed: ${confirmed.amountCents} ${reg.salon.currency}');

    // 10. Customer 1 sees the visit as done & paid; no active booking.
    expect(await c1.getCurrentBooking(), isNull);
    final history = await c1.getCustomerHistory();
    final visit = history.firstWhere((v) => v.booking.id == booking1.id);
    expect(visit.booking.status, BookingStatus.done);
    expect(visit.barberName, 'خالد');
    expect(visit.payment!.status, PaymentStatus.confirmed);
    expect(visit.payment!.amountCents, 5000);
    log('customer 1 history: ${visit.booking.status.name}, paid ${visit.payment!.amountCents}');

    // 11. Manager report for the work day shows the revenue.
    final workDate = DateTime.parse(visit.booking.workDate!);
    final report = await manager.getManagerReports(from: workDate, to: workDate);
    final total = (report['revenue'] as Map)['total'] as Map;
    expect(total['confirmed'], 5000);
    final perBarber = ((report['revenue'] as Map)['perBarber'] as List).cast<Map>();
    expect(perBarber.firstWhere((r) => r['staffId'] == a.id)['confirmed'], 5000);
    log('manager report ${visit.booking.workDate}: revenue confirmed ${total['confirmed']}, awaiting ${total['awaiting']}');

    // Customer 2 is still waiting with barber B.
    expect((await c2.getCurrentBooking())!.booking.barberId, barberB['id']);

    await engineA.dispose();
    await engineB.dispose();
    for (final c in [manager, apiA, apiB, c1, c2]) {
      await c.logout();
    }
    log('PASS');
  });
}

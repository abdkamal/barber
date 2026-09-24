import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_api/saloni_api.dart' as sa;
import 'package:saloni_staff/core/compat_http_client.dart';
import 'package:saloni_staff/core/format.dart';
import 'package:saloni_staff/data/models.dart';
import 'package:saloni_staff/data/queue_logic.dart';

QueueEntry _e(String id, sa.BookingStatus status, int pos, {bool used = false, DateTime? start}) {
  final now = DateTime.utc(2026, 9, 24, 10);
  return QueueEntry(
    id: id,
    customerId: 'c$id',
    barberId: 'b',
    name: id,
    status: status,
    serviceIds: const ['s'],
    kind: sa.BookingKind.queue,
    originalEta: now,
    eta: now.add(Duration(minutes: 30 * pos)),
    durationMin: 30,
    priceCents: 4000,
    position: pos,
    postponementUsed: used,
    actualStart: start,
  );
}

sa.DeviceEvent _ev(sa.DeviceEventType t, String? id, [Map<String, dynamic> p = const {}]) => sa.DeviceEvent(
      id: 'e',
      deviceSeq: 1,
      type: t,
      bookingId: id,
      occurredAt: DateTime.utc(2026, 9, 24, 10),
      approximate: false,
      payload: p,
    );

void main() {
  final now = DateTime.utc(2026, 9, 24, 10);
  final services = [const sa.Service(id: 's', name: 'حلاقة', baseDurationMin: 30, priceCents: 4000)];

  test('التأجيل (ق21): ينزل بعدد الأدوار، يُعلَّم مستخدمًا، ويُستدعى التالي', () {
    final q = [
      _e('a', sa.BookingStatus.called, 1),
      _e('b', sa.BookingStatus.waiting, 2),
      _e('c', sa.BookingStatus.waiting, 3),
    ];
    final r = applyEvent(q, _ev(sa.DeviceEventType.postponed, 'a', {'steps': 2}), services, now);
    final order = activeOrdered(r).map((e) => e.id).toList();
    expect(order, ['b', 'c', 'a']);
    expect(r.firstWhere((e) => e.id == 'a').postponementUsed, isTrue);
    expect(r.firstWhere((e) => e.id == 'b').status, sa.BookingStatus.called);
  });

  test('ق22: بدء زبون قبل المستدعى = تأجيل للمستدعى', () {
    final q = [_e('a', sa.BookingStatus.called, 1), _e('w', sa.BookingStatus.waiting, 2)];
    final r = applyEvent(q, _ev(sa.DeviceEventType.serviceStarted, 'w'), services, now);
    expect(r.firstWhere((e) => e.id == 'w').status, sa.BookingStatus.inService);
    final a = r.firstWhere((e) => e.id == 'a');
    expect(a.status, sa.BookingStatus.waiting);
    expect(a.postponementUsed, isTrue);
  });

  test('الإنهاء يجعل الدفع بانتظار التأكيد ويعيد حساب الأوقات', () {
    final q = [
      _e('a', sa.BookingStatus.inService, 0, start: now.subtract(const Duration(minutes: 10))),
      _e('b', sa.BookingStatus.waiting, 1),
    ];
    final r = applyEvent(q, _ev(sa.DeviceEventType.serviceFinished, 'a'), services, now);
    expect(r.first.status, sa.BookingStatus.done);
    expect(r.first.payment, sa.PaymentStatus.awaitingConfirmation);
    expect(r.last.eta, now);
  });

  test('قاعدة ق3: العمل المعروف المتبقي', () {
    final q = [
      _e('a', sa.BookingStatus.inService, 0, start: now.subtract(const Duration(minutes: 10))),
      _e('b', sa.BookingStatus.waiting, 1),
    ];
    expect(remainingWorkMinutes(q, now), 20 + 30);
  });

  test('توافق الجلسة: salon ككائن يتحول إلى رمز مع حفظ بياناته', () {
    final json = jsonDecode(jsonEncode({
      'accessToken': 'a',
      'refreshToken': 'r',
      'role': 'barber',
      'salon': {'code': 'RAHA-27', 'name': 'صالون', 'status': 'active', 'currency': 'SAR'},
      'account': {'id': '1', 'name': 'خالد'},
    })) as Map<String, dynamic>;
    Map<String, dynamic>? salon;
    Map<String, dynamic>? account;
    normalizeSessionJson(json, (s, a) {
      salon = s;
      account = a;
    });
    final session = sa.Session.fromJson(json);
    expect(session.salonCode, 'RAHA-27');
    expect(salon?['name'], 'صالون');
    expect(account?['name'], 'خالد');
  });

  test('العملة والأرقام', () {
    expect(Currency.of('SAR').format(6000), '60 ر.س');
    expect(Currency.of('SAR').format(124000), '1,240 ر.س');
    expect(Currency.of('KWD').format(1500), '1.500 د.ك');
    expect(Currency.of('SAR').parse('٦٠'), 6000);
    numeralStyle = NumeralStyle.eastern;
    expect(digits('10:05'), '١٠:٠٥');
    numeralStyle = NumeralStyle.latin;
  });

  test('معاينة الأثر: شكل السيرفر (changes + pastClosing)', () {
    final p = ImpactPreview.fromJson({
      'changes': [
        {'bookingId': 'b', 'customerName': 'عبدالله', 'before': '2026-09-24T10:00:00Z', 'after': '2026-09-24T10:35:00Z', 'deltaMin': 35, 'pastClosing': false, 'notify': true},
      ],
      'pastClosing': [
        {'bookingId': 'c', 'customerName': 'ريان', 'end': '2026-09-24T23:30:00Z'},
      ],
      'newDurationMin': 45,
    });
    expect(p.items, hasLength(2));
    expect(p.notified.single.name, 'عبدالله');
    expect(p.pastClosing.single.bookingId, 'c');
    expect(p.newDurationMin, 45);
  });
}

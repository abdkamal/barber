import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_api/saloni_api.dart' as sa;
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

  test('الجلسة: بيانات الصالون والحساب من الحزمة مباشرة', () {
    final session = sa.Session.fromJson({
      'accessToken': 'a',
      'refreshToken': 'r',
      'role': 'barber',
      'salon': {'code': 'RAHA-27', 'name': 'صالون', 'status': 'active', 'currency': 'SAR'},
      'account': {'id': '1', 'name': 'خالد'},
    });
    final meta = SalonMeta.fromInfo(session.salon);
    expect(session.salonCode, 'RAHA-27');
    expect(meta.name, 'صالون');
    expect(meta.currency, 'SAR');
    expect(session.account?.name, 'خالد');
  });

  test('إدخال الطابور من حجز السيرفر (الاسم والهاتف والمدة والسعر والوقت الحالي)', () {
    final b = sa.Booking.fromJson({
      'id': 'b1',
      'customerId': 'c1',
      'barberId': 'x',
      'serviceIds': ['s1'],
      'kind': 'queue',
      'status': 'called',
      'originalEta': '2026-09-24T10:00:00Z',
      'source': 'app',
      'customerName': 'سالم',
      'customerPhone': '0500000000',
      'priceCents': 5500,
      'estimatedDurationMin': 35,
      'eta': '2026-09-24T10:20:00Z',
      'calledAt': '2026-09-24T10:18:00Z',
      'serveLate': true,
    });
    final e = QueueEntry.from(b, const [], pastClosing: true);
    expect(e.name, 'سالم');
    expect(e.phone, '0500000000');
    expect(e.durationMin, 35);
    expect(e.priceCents, 5500);
    expect(e.eta, DateTime.utc(2026, 9, 24, 10, 20));
    expect(e.calledAt, isNotNull);
    expect(e.closingDecided, isTrue);
    final again = QueueEntry.from(e.toBooking(), const [], local: e.extrasJson());
    expect(again.name, 'سالم');
    expect(again.pastClosing, isTrue);
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
    final p = ImpactPreview.fromImpact(sa.StaffImpact.fromJson({
      'bookingId': 'a',
      'changes': [
        {'bookingId': 'b', 'customerName': 'عبدالله', 'before': '2026-09-24T10:00:00Z', 'after': '2026-09-24T10:35:00Z', 'deltaMin': 35, 'pastClosing': false, 'notify': true},
      ],
      'pastClosing': [
        {'bookingId': 'c', 'customerName': 'ريان', 'end': '2026-09-24T23:30:00Z'},
      ],
      'newDurationMin': 45,
    }));
    expect(p.items, hasLength(2));
    expect(p.notified.single.name, 'عبدالله');
    expect(p.pastClosing.single.bookingId, 'c');
    expect(p.newDurationMin, 45);
  });
}

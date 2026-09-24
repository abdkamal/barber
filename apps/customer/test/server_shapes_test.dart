import 'package:customer/screens/history/history_screen.dart';
import 'package:customer/screens/tracking/change_time_screen.dart';
import 'package:customer/screens/tracking/track_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_api/saloni_api.dart';

import 'fakes/fake_customer_api.dart';
import 'support/pump_app.dart';

/// حجز بالشكل الذي يرسله السيرفر (`BookingDto`).
Map<String, dynamic> bookingJson({String status = 'waiting'}) {
  final eta = DateTime.now().toUtc().add(const Duration(minutes: 30));
  return {
    'id': 'bk-1',
    'customerId': 'c-1',
    'barberId': 'b-1',
    'serviceIds': ['svc-1'],
    'kind': 'queue',
    'requestedAt': null,
    'status': status,
    'queuePosition': 1,
    'originalEta': eta.toIso8601String(),
    'lastShownEta': null,
    'postponementUsed': false,
    'actualStart': status == 'done' ? eta.toIso8601String() : null,
    'actualEnd': null,
    'source': 'app',
    'walkIn': false,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'workDate': '2026-09-24',
    'customerName': 'سالم',
    'services': [
      {'id': 'svc-1', 'name': 'حلاقة شعر', 'priceCents': 4000, 'baseDurationMin': 30},
    ],
    'priceCents': 4000,
    'estimatedDurationMin': 30,
    'eta': eta.toIso8601String(),
    'etaEnd': eta.add(const Duration(minutes: 30)).toIso8601String(),
    'calledAt': null,
    'offerExpiresAt': null,
    'lastChangeReason': null,
    'serveLate': false,
    'needsReview': false,
  };
}

CurrentBooking currentJson() {
  final b = bookingJson();
  return CurrentBooking.fromJson({
    'booking': b,
    'eta': b['eta'],
    'etaEnd': b['etaEnd'],
    'originalEta': b['originalEta'],
    'lastChangeReason': null,
    'lastChangeReasonCode': null,
    'status': 'waiting',
    'progress': {'done': 1, 'ahead': 1},
    'live': true,
    'dayState': 'connected',
    'lastUpdateAt': DateTime.now().toUtc().toIso8601String(),
    'barber': {'id': 'b-1', 'name': 'خالد الحربي'},
    'serverTime': DateTime.now().toUtc().toIso8601String(),
  });
}

void main() {
  testWidgets('المتابعة تعرض اسم الحلاق والخدمات من السيرفر', (tester) async {
    final api = FakeCustomerApi()..setCurrentBooking(currentJson());
    await pumpSaloniApp(tester, TrackScreen(api: api, onChangeTime: (_) {}, onCancel: (_) {}));
    await tester.pumpAndSettle();
    expect(find.textContaining('خالد الحربي'), findsWidgets);
    expect(find.textContaining('حلاقة شعر'), findsWidgets);
  });

  testWidgets('لا حجز نشط ({booking: null}) يعيد المضيف لشاشة الحجز', (tester) async {
    final api = FakeCustomerApi(); // getCurrentBooking → null
    var noActive = 0;
    await pumpSaloniApp(
      tester,
      TrackScreen(api: api, onChangeTime: (_) {}, onCancel: (_) {}, onNoActiveBooking: () => noActive++),
    );
    await tester.pumpAndSettle();
    expect(noActive, 1);
  });

  testWidgets('تعديل الوقت: 409 SLOT_UNAVAILABLE مع عرض ← بطاقة العرض ثم القبول بـ offerId', (tester) async {
    final api = FakeCustomerApi();
    final start = DateTime.now().toUtc().add(const Duration(hours: 2));
    api.nextChangeTimeError = ApiError.fromJson({
      'error': {
        'code': 'SLOT_UNAVAILABLE',
        'message': 'الساعة المطلوبة غير متاحة',
        'details': {
          'offer': {
            'barberId': 'b-1',
            'barberName': 'خالد الحربي',
            'start': start.toIso8601String(),
            'end': start.add(const Duration(minutes: 30)).toIso8601String(),
            'durationMin': 30,
            'price': 4000,
            'outcome': 'offer',
            'offerId': 'offer-9',
            'offerExpiresAt': DateTime.now().toUtc().add(const Duration(minutes: 2)).toIso8601String(),
          },
        },
      },
    }, statusCode: 409);
    Booking? changed;
    await pumpSaloniApp(
      tester,
      ChangeTimeScreen(api: api, current: currentJson(), onChanged: (b) => changed = b),
    );
    await tester.pump();
    await tester.tap(find.text('تأكيد التعديل'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('حجزك الحالي باقٍ كما هو'), findsOneWidget);
    expect(find.text('تأكيد التعديل'), findsNothing);

    await tester.tap(find.text('احجز هذا الوقت'));
    await tester.pump();
    await tester.pump();
    expect(api.createdBookingCalls.single['offerId'], 'offer-9');
    expect(changed, isNotNull);
  });

  testWidgets('السجل يعرض الزيارة المنجزة المدفوعة من GET /customer/history', (tester) async {
    final api = FakeCustomerApi(history: [
      HistoryVisit.fromJson({
        ...bookingJson(status: 'done'),
        'barberName': 'خالد الحربي',
        'payment': {'status': 'confirmed', 'amountCents': 4000},
      }),
    ]);
    await pumpSaloniApp(tester, HistoryScreen(api: api, currency: 'ر.س'));
    await tester.pumpAndSettle();
    expect(find.text('خالد الحربي'), findsOneWidget);
    expect(find.text('حلاقة شعر'), findsOneWidget);
    expect(find.text('40 ر.س'), findsOneWidget);
  });
}

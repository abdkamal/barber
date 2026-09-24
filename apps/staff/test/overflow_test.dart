import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

/// فحص تجاوز RTL على عرض 360 (بلا صور مرجعية): أي تجاوز يُفشل الاختبار تلقائيًا.
void main() {
  FakeServer busyServer(String role) {
    final s = FakeServer(role: role)
      ..booking(id: 'b1', name: 'محمد عبدالرحمن العتيبي', status: 'in_service', startedMinAgo: 50, position: 0, durationMin: 45)
      ..booking(id: 'b2', name: 'فهد القحطاني', status: 'called', position: 1)
      ..booking(id: 'b3', name: 'عبدالله Alexander', position: 2, walkIn: true, serviceIds: ['s-hair', 's-both', 's-beard'])
      ..booking(id: 'b4', name: 'ريان', position: 3);
    s.closingWarnings = ['b4'];
    s.managerQueues = [
      s.queueBarber(id: 'x', name: 'خالد الحربي', state: 'disconnected', queue: [
        s.bookingJson(id: 'q1', name: 'فهد القحطاني الطويل الاسم', status: 'called', serviceIds: ['s-both'], durationMin: 45),
      ]),
    ];
    return s;
  }

  Future<void> visit(WidgetTester tester, List<String> paths) async {
    for (final p in paths) {
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go(p);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: p);
    }
  }

  for (final scale in [1.0, 1.3]) {
    testWidgets('الحلاق — كل الشاشات على 360 (تكبير $scale)', (tester) async {
      final h = await pumpStaffApp(tester, busyServer('barber'), textScale: scale);
      expect(MediaQuery.textScalerOf(tester.element(find.byType(Scaffold).first)).scale(10), closeTo(10 * scale, 0.01));
      await visit(tester, ['/b/queue', '/b/payments', '/b/breaks', '/b/more', '/b/walkin']);
      await teardownApp(tester, h);
    });
  }

  testWidgets('المدير — كل الشاشات على 360', (tester) async {
    final h = await pumpStaffApp(tester, busyServer('manager'));
    await visit(tester, [
      '/m/queues',
      '/m/reports',
      '/m/salon',
      '/m/settings',
      '/m/staff',
      '/m/customers',
      '/m/schedules',
      '/b/queue',
    ]);
    expect(find.text('طابوري'), findsWidgets);
    await teardownApp(tester, h);
  });

  testWidgets('الدخول والتسجيل على 360', (tester) async {
    final h = await pumpStaffApp(tester, FakeServer(), signedIn: false);
    expect(tester.takeException(), isNull);
    await visit(tester, ['/signup', '/reset', '/login']);
    await teardownApp(tester, h);
  });
}

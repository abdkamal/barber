import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

GoRouter _router(WidgetTester tester) => GoRouter.of(tester.element(find.byType(Scaffold).first));

void main() {
  group('شاشة الزبائن — إجراءات المدير الجديدة (H2)', () {
    testWidgets('فك ربط سجل الحاضر', (tester) async {
      final server = FakeServer(role: 'manager')
        ..managerCustomers = [
          {
            'id': 'cus-1',
            'name': 'سالم',
            'phone': '0500000001',
            'status': 'active',
            'linked_walk_in_id': 'walk-1',
          },
        ];
      final h = await pumpStaffApp(tester, server);
      _router(tester).go('/m/customers');
      await settle(tester);

      await tester.tap(find.text('سالم'));
      await settle(tester);
      await tester.tap(find.text('فك ربط سجل الحاضر'));
      await settle(tester);
      // تأكيد الإجراء الهدّام.
      await tester.tap(find.text('فك الربط'));
      await settle(tester);

      expect(server.unlinkedCustomerIds, ['cus-1']);
      await teardownApp(tester, h);
    });

    testWidgets('تعديل رقم الهاتف يرسل PUT /manager/customers/{id}/phone', (tester) async {
      final server = FakeServer(role: 'manager')
        ..managerCustomers = [
          {'id': 'cus-2', 'name': 'فهد', 'phone': '0500000002', 'status': 'active'},
        ];
      final h = await pumpStaffApp(tester, server);
      _router(tester).go('/m/customers');
      await settle(tester);

      await tester.tap(find.text('فهد'));
      await settle(tester);
      await tester.tap(find.text('تعديل رقم الهاتف'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).last, '0511111111');
      await tester.tap(find.text('حفظ'));
      await settle(tester);

      expect(server.phoneUpdates, [
        {'id': 'cus-2', 'phone': '0511111111'}
      ]);
      await teardownApp(tester, h);
    });

    testWidgets('الإفراج عن الرقم لحساب موقوف', (tester) async {
      final server = FakeServer(role: 'manager')
        ..managerCustomers = [
          {'id': 'cus-3', 'name': 'ريان', 'phone': '0500000003', 'status': 'suspended'},
        ];
      final h = await pumpStaffApp(tester, server);
      _router(tester).go('/m/customers');
      await settle(tester);

      await tester.tap(find.text('ريان'));
      await settle(tester);
      await tester.tap(find.text('الإفراج عن الرقم'));
      await settle(tester);
      await tester.tap(find.text('الإفراج'));
      await settle(tester);

      expect(server.releasedPhoneCustomerIds, ['cus-3']);
      await teardownApp(tester, h);
    });
  });
}

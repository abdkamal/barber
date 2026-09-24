import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_ui_gallery/main.dart';

void main() {
  testWidgets('يُبنى المعرض بلا أخطاء (هاتف 360px)', (tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const GalleryApp());
    await tester.pump();
    expect(tester.takeException(), isNull);

    // التبديل إلى الوضع الفاتح واتجاه LTR للفحص.
    await tester.tap(find.byIcon(Icons.swap_horiz));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.light_mode));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

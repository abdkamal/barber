import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_ui/saloni_ui.dart';

/// يغلّف الودجت بما يلزمها للعمل في اختبار: `ProviderScope` (لبعض الودجت
/// المشتركة التي تعتمد على Riverpod مثل `OnboardingTip`)، سمة «صالوني»،
/// واتجاه RTL كامل — كما يعمل التطبيق فعليًا.
Future<void> pumpSaloniApp(
  WidgetTester tester,
  Widget child, {
  double textScale = 1.0,
  Size surfaceSize = const Size(390, 844),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: SaloniTheme.dark(),
        debugShowCheckedModeBanner: false,
        builder: (context, widgetChild) => Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: widgetChild ?? const SizedBox.shrink(),
          ),
        ),
        home: child,
      ),
    ),
  );
}

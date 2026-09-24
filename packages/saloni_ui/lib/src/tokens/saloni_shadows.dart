import 'package:flutter/material.dart';

/// Shadow tokens — `design/design-system/tokens.json` → shadow.
///
/// في الليل الظل عمق لا زخرفة؛ الحدود والطبقات أولًا.
abstract final class SaloniShadows {
  static const List<BoxShadow> shadow1Dark = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.35),
      offset: Offset(0, 1),
      blurRadius: 2,
    ),
  ];

  static const List<BoxShadow> shadow1Light = [
    BoxShadow(
      color: Color.fromRGBO(15, 27, 45, 0.06),
      offset: Offset(0, 1),
      blurRadius: 2,
    ),
    BoxShadow(
      color: Color.fromRGBO(15, 27, 45, 0.05),
      offset: Offset(0, 1),
      blurRadius: 3,
    ),
  ];

  static const List<BoxShadow> shadow2Dark = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.40),
      offset: Offset(0, 12),
      blurRadius: 32,
    ),
  ];

  static const List<BoxShadow> shadow2Light = [
    BoxShadow(
      color: Color.fromRGBO(31, 95, 134, 0.12),
      offset: Offset(0, 10),
      blurRadius: 28,
    ),
  ];

  static const List<BoxShadow> shadow3Dark = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.55),
      offset: Offset(0, -12),
      blurRadius: 36,
    ),
  ];

  static const List<BoxShadow> shadow3Light = [
    BoxShadow(
      color: Color.fromRGBO(15, 27, 45, 0.14),
      offset: Offset(0, -10),
      blurRadius: 32,
    ),
  ];
}

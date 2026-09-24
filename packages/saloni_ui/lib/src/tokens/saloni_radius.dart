import 'package:flutter/widgets.dart';

/// Radius tokens — `design/design-system/tokens.json` → radius.
abstract final class SaloniRadius {
  static const double sm = 10;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 22;
  static const double full = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius fullAll = BorderRadius.all(Radius.circular(full));
}

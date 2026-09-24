import 'package:flutter/painting.dart';

/// Font family tokens — `design/design-system/tokens.json` → type.families.
abstract final class SaloniFonts {
  static const String display = 'El Messiri';
  static const String text = 'IBM Plex Sans Arabic';
  static const String mono = 'IBM Plex Mono';
}

/// Type-style tokens — `design/design-system/tokens.json` → type.groups.
///
/// Every style is named exactly as in the tokens file. Colors are NOT baked
/// in here (tokens.json does not define one); apply `SaloniColors.ink` /
/// `.inkMuted` etc. per usage, or use [SaloniTheme] which wires these into a
/// [TextTheme] with `ink` as the default color.
abstract final class SaloniTextStyles {
  // ---- Display (El Messiri) ----
  static const TextStyle display = TextStyle(
    fontFamily: SaloniFonts.display,
    fontSize: 34,
    height: 44 / 34,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle title1 = TextStyle(
    fontFamily: SaloniFonts.display,
    fontSize: 26,
    height: 36 / 26,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle title2 = TextStyle(
    fontFamily: SaloniFonts.display,
    fontSize: 20,
    height: 30 / 20,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle title3 = TextStyle(
    fontFamily: SaloniFonts.display,
    fontSize: 17,
    height: 26 / 17,
    fontWeight: FontWeight.w600,
  );

  // ---- Text (IBM Plex Sans Arabic) ----
  static const TextStyle bodyLg = TextStyle(
    fontFamily: SaloniFonts.text,
    fontSize: 17,
    height: 28 / 17,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle body = TextStyle(
    fontFamily: SaloniFonts.text,
    fontSize: 15,
    height: 24 / 15,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontFamily: SaloniFonts.text,
    fontSize: 15,
    height: 24 / 15,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle label = TextStyle(
    fontFamily: SaloniFonts.text,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: SaloniFonts.text,
    fontSize: 13,
    height: 20 / 13,
    fontWeight: FontWeight.w400,
  );

  // ---- Numerals (El Messiri, tabular figures) ----
  static const TextStyle timeHero = TextStyle(
    fontFamily: SaloniFonts.display,
    fontSize: 48,
    height: 52 / 48,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle time = TextStyle(
    fontFamily: SaloniFonts.display,
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle stat = TextStyle(
    fontFamily: SaloniFonts.display,
    fontSize: 30,
    height: 38 / 30,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // ---- Code (IBM Plex Mono) ----
  static const TextStyle code = TextStyle(
    fontFamily: SaloniFonts.mono,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w500,
    letterSpacing: 15 * 0.08,
  );
}

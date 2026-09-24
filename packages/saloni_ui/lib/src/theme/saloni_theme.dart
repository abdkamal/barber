import 'package:flutter/material.dart';

import '../tokens/saloni_colors.dart';
import '../tokens/saloni_radius.dart';
import '../tokens/saloni_sizes.dart';
import '../tokens/saloni_typography.dart';

/// Builds the app [ThemeData] for «صالوني» — Material 3, wired to the design
/// tokens. Dark is the primary/default theme (ق38); light is derived.
abstract final class SaloniTheme {
  static ThemeData dark() => _build(SaloniColors.dark, Brightness.dark);

  static ThemeData light() => _build(SaloniColors.light, Brightness.light);

  static ThemeData _build(SaloniColors c, Brightness brightness) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      secondary: c.steel,
      onSecondary: c.onPrimary,
      error: c.danger,
      onError: c.onDanger,
      surface: c.surface,
      onSurface: c.ink,
      surfaceContainerHighest: c.surfaceRaised,
      outline: c.lineStrong,
      outlineVariant: c.line,
    );

    final textTheme = _textTheme(c.ink);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: c.surface,
      canvasColor: c.surface,
      fontFamily: SaloniFonts.text,
      textTheme: textTheme,
      dividerColor: c.line,
      splashFactory: InkRipple.splashFactory,
      focusColor: c.focus,
      extensions: [c],
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.ink,
        elevation: 0,
        titleTextStyle: SaloniTextStyles.title2.copyWith(color: c.ink),
      ),
      cardTheme: CardThemeData(
        color: c.surfaceRaised,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: SaloniRadius.lgAll,
          side: BorderSide(color: c.line),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceRaised,
        hintStyle: SaloniTextStyles.bodyLg.copyWith(color: c.inkSubtle),
        border: OutlineInputBorder(
          borderRadius: SaloniRadius.mdAll,
          borderSide: BorderSide(color: c.lineStrong),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          minimumSize: const Size.fromHeight(SaloniSizes.controlMd),
          shape: RoundedRectangleBorder(borderRadius: SaloniRadius.mdAll),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.onPrimary
              : c.lineStrong,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.primary
              : c.surfaceSunken,
        ),
      ),
      visualDensity: VisualDensity.standard,
    );
  }

  static TextTheme _textTheme(Color ink) {
    TextStyle c(TextStyle s) => s.copyWith(color: ink);
    return TextTheme(
      displayLarge: c(SaloniTextStyles.display),
      headlineLarge: c(SaloniTextStyles.title1),
      headlineMedium: c(SaloniTextStyles.title2),
      headlineSmall: c(SaloniTextStyles.title3),
      titleLarge: c(SaloniTextStyles.title3),
      bodyLarge: c(SaloniTextStyles.bodyLg),
      bodyMedium: c(SaloniTextStyles.body),
      bodySmall: c(SaloniTextStyles.caption),
      labelLarge: c(SaloniTextStyles.label),
      labelMedium: c(SaloniTextStyles.label),
      labelSmall: c(SaloniTextStyles.caption),
    );
  }
}

/// Convenience accessor: `context.saloniColors`.
extension SaloniColorsContext on BuildContext {
  SaloniColors get saloniColors =>
      Theme.of(this).extension<SaloniColors>() ?? SaloniColors.dark;
}

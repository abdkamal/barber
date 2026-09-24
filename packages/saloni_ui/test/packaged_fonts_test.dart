import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_ui/saloni_ui.dart';

/// Styles must reference the package-qualified family (`packages/saloni_ui/…`)
/// because that is how Flutter registers fonts declared by a dependency. The
/// consuming-app proof (font manifest lookup) lives in
/// `example/test/packaged_fonts_test.dart`.
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  final all = <String, TextStyle>{
    'display': SaloniTextStyles.display,
    'title1': SaloniTextStyles.title1,
    'title2': SaloniTextStyles.title2,
    'title3': SaloniTextStyles.title3,
    'bodyLg': SaloniTextStyles.bodyLg,
    'body': SaloniTextStyles.body,
    'bodyStrong': SaloniTextStyles.bodyStrong,
    'label': SaloniTextStyles.label,
    'caption': SaloniTextStyles.caption,
    'timeHero': SaloniTextStyles.timeHero,
    'time': SaloniTextStyles.time,
    'stat': SaloniTextStyles.stat,
    'code': SaloniTextStyles.code,
  };

  for (final e in all.entries) {
    test('${e.key} references a family declared by this package', () {
      final family = e.value.fontFamily!;
      expect(family, startsWith('packages/saloni_ui/'));
      final bare = family.substring('packages/saloni_ui/'.length);
      expect(pubspec, contains('- family: $bare'));
    });
  }

  test('theme text uses the packaged families', () {
    for (final theme in [SaloniTheme.dark(), SaloniTheme.light()]) {
      expect(theme.textTheme.bodyMedium?.fontFamily, SaloniFonts.textFamily);
      expect(theme.textTheme.headlineMedium?.fontFamily,
          anyOf(SaloniFonts.displayFamily, SaloniFonts.textFamily));
    }
  });
}

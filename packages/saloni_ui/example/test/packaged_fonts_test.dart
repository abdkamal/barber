import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_ui/saloni_ui.dart';

/// This gallery consumes `saloni_ui` as a dependency — exactly like the two
/// apps. Flutter registers a dependency's fonts as `packages/saloni_ui/<family>`,
/// so the families referenced by the design-system styles must be present in
/// this app's font manifest, or the fonts silently fall back to the default.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Map<String, List<String>>> manifest() async {
    final raw = await rootBundle.loadString('FontManifest.json');
    final list = jsonDecode(raw) as List<dynamic>;
    return {
      for (final f in list.cast<Map<String, dynamic>>())
        f['family'] as String: [
          for (final a in (f['fonts'] as List).cast<Map<String, dynamic>>())
            a['asset'] as String,
        ],
    };
  }

  test('every family used by SaloniTextStyles is registered in the consuming app', () async {
    final families = await manifest();
    final styles = <String, TextStyle>{
      'display': SaloniTextStyles.display,
      'title1': SaloniTextStyles.title1,
      'body': SaloniTextStyles.body,
      'label': SaloniTextStyles.label,
      'timeHero': SaloniTextStyles.timeHero,
      'stat': SaloniTextStyles.stat,
      'code': SaloniTextStyles.code,
    };
    for (final e in styles.entries) {
      expect(families.keys, contains(e.value.fontFamily),
          reason: '${e.key} uses ${e.value.fontFamily}');
    }
    expect(families[SaloniFonts.displayFamily], isNotEmpty);
    expect(families[SaloniFonts.textFamily], hasLength(3));
    expect(families[SaloniFonts.monoFamily], isNotEmpty);
  });

  test('the theme default font resolves to the packaged text family', () async {
    final families = await manifest();
    final theme = SaloniTheme.dark();
    expect(theme.textTheme.bodyMedium?.fontFamily, SaloniFonts.textFamily);
    expect(families.keys, contains(theme.textTheme.bodyMedium?.fontFamily));
  });

  test('the packaged font files and their OFL licences load from the bundle', () async {
    final families = await manifest();
    for (final assets in families.values) {
      for (final a in assets.where((a) => a.startsWith('packages/saloni_ui/'))) {
        final data = await rootBundle.load(a);
        expect(data.lengthInBytes, greaterThan(10000), reason: a);
      }
    }
    for (final key in saloniFontLicenseAssets.values) {
      expect(await rootBundle.loadString(key), contains('SIL OPEN FONT LICENSE'), reason: key);
    }
  });

  test('registerSaloniFontLicenses exposes the OFL texts on the licence page', () async {
    registerSaloniFontLicenses();
    final packages = <String>{};
    await for (final entry in LicenseRegistry.licenses) {
      packages.addAll(entry.packages);
    }
    expect(packages, containsAll([SaloniFonts.display, SaloniFonts.text, SaloniFonts.mono]));
  });
}

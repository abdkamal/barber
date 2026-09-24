import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'saloni_typography.dart';

/// Asset keys of the OFL licence texts bundled with the fonts, as seen from an
/// app that depends on `saloni_ui`.
const saloniFontLicenseAssets = <String, String>{
  SaloniFonts.display: 'packages/saloni_ui/assets/fonts/licenses/OFL-ElMessiri.txt',
  SaloniFonts.text: 'packages/saloni_ui/assets/fonts/licenses/OFL-IBMPlexSansArabic.txt',
  SaloniFonts.mono: 'packages/saloni_ui/assets/fonts/licenses/OFL-IBMPlexMono.txt',
};

bool _registered = false;

/// Adds the SIL OFL 1.1 licences of the bundled fonts to Flutter's
/// [LicenseRegistry] so they appear on the app's licence page
/// (`showLicensePage`). Call once from `main()`; later calls do nothing.
void registerSaloniFontLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    for (final entry in saloniFontLicenseAssets.entries) {
      final text = await rootBundle.loadString(entry.value);
      yield LicenseEntryWithLineBreaks([entry.key], text);
    }
  });
}

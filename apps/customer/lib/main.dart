import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saloni_api/saloni_api.dart' show initializeSaloniTimeZones;
import 'package:saloni_ui/saloni_ui.dart' show registerSaloniFontLicenses;

import 'app/app.dart';

void main() {
  // بيانات المناطق الزمنية لعرض الأوقات بتوقيت الصالون لا الجهاز (I5).
  initializeSaloniTimeZones();
  registerSaloniFontLicenses();
  runApp(const ProviderScope(child: SaloniCustomerApp()));
}

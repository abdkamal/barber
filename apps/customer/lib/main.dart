import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saloni_ui/saloni_ui.dart' show registerSaloniFontLicenses;

import 'app/app.dart';

void main() {
  registerSaloniFontLicenses();
  runApp(const ProviderScope(child: SaloniCustomerApp()));
}

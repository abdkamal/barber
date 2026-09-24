import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saloni_ui/saloni_ui.dart' show registerSaloniFontLicenses;

import 'app.dart';
import 'state/app_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerSaloniFontLicenses();
  // منفذ اتصال الخدمة الأمامية (design.md §1) — لا أثر له خارج أندرويد.
  if (!kIsWeb) {
    FlutterForegroundTask.initCommunicationPort();
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  final services = await AppServices.create();
  runApp(
    ProviderScope(
      overrides: [servicesProvider.overrideWithValue(services)],
      child: const WithForegroundTask(child: StaffApp()),
    ),
  );
}

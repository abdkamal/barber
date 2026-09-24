import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saloni_api/saloni_api.dart' show NotificationKind;
import 'package:saloni_ui/saloni_ui.dart';

import 'core/config.dart';
import 'core/platform/push.dart';
import 'features/auth/hold_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/reset_screen.dart';
import 'features/barber/breaks_screen.dart';
import 'features/barber/more_screen.dart';
import 'features/barber/payments_screen.dart';
import 'features/barber/queue_screen.dart';
import 'features/barber/walkin_screen.dart';
import 'features/common/about_screen.dart';
import 'features/common/shells.dart';
import 'features/manager/customers_screen.dart';
import 'features/manager/queues_screen.dart';
import 'features/manager/recovered_screen.dart';
import 'features/manager/reports_screen.dart';
import 'features/manager/salon_screen.dart';
import 'features/manager/schedules_screen.dart';
import 'features/manager/settings_screen.dart';
import 'features/manager/staff_screen.dart';
import 'features/signup/signup_screen.dart';
import 'state/app_services.dart';

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// مسارات المدير — مخفية عن الحلاق (يُعاد توجيهه).
bool isManagerPath(String p) => p == '/m' || p.startsWith('/m/');

String homeFor(AuthController auth) => auth.isManager ? '/m/queues' : '/b/queue';

GoRouter buildRouter(AuthController auth) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: auth,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final publicPaths = {'/login', '/reset', '/signup'};
      switch (auth.status) {
        case AuthStatus.unknown:
          return loc == '/splash' ? null : '/splash';
        case AuthStatus.signedOut:
          // ق40: جهاز يحمل إجراءات لم تُرفع لحساب لا يستطيع رفعها — «سلّم الجهاز للمدير».
          if (auth.hold != null) return loc == '/hold' ? null : '/hold';
          return publicPaths.contains(loc) ? null : '/login';
        case AuthStatus.signedIn:
          if (loc == '/splash' || loc == '/hold' || publicPaths.contains(loc)) return homeFor(auth);
          if (isManagerPath(loc) && !auth.isManager) return '/b/queue';
          return null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const _Splash()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/reset', builder: (_, __) => const ResetScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(path: '/hold', builder: (_, __) => const HoldScreen()),
      GoRoute(path: '/about', builder: (_, __) => const AboutScreen()),
      GoRoute(path: '/b/walkin', builder: (_, __) => const WalkInScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => BarberShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/b/queue', builder: (_, __) => const QueueScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/b/payments', builder: (_, __) => const PaymentsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/b/breaks', builder: (_, __) => const BreaksScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/b/more', builder: (_, __) => const MoreScreen()),
          ]),
        ],
      ),
      GoRoute(path: '/m/staff', builder: (_, __) => const StaffScreen()),
      GoRoute(path: '/m/customers', builder: (_, __) => const CustomersScreen()),
      GoRoute(path: '/m/schedules', builder: (_, __) => const SchedulesScreen()),
      GoRoute(path: '/m/recovered', builder: (_, __) => const RecoveredScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => ManagerShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/m/queues', builder: (_, __) => const QueuesScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/m/reports', builder: (_, __) => const ReportsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/m/salon', builder: (_, __) => const SalonScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/m/settings', builder: (_, __) => const ManagerSettingsScreen()),
          ]),
        ],
      ),
    ],
  );
}

class StaffApp extends ConsumerStatefulWidget {
  const StaffApp({super.key});

  @override
  ConsumerState<StaffApp> createState() => _StaffAppState();
}

class _StaffAppState extends ConsumerState<StaffApp> {
  late final GoRouter _router;
  StreamSubscription<PushMessage>? _push;

  @override
  void initState() {
    super.initState();
    // رسائل FCM أثناء فتح التطبيق تُعرض داخل التطبيق (ق12).
    _push = ref.read(servicesProvider).push.messages.listen((m) {
      final text = [m.title, m.body].whereType<String>().where((t) => t.isNotEmpty).join(' — ');
      if (text.isEmpty) return;
      scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(content: Text(text)));
      // تنبيهات الطابور (استدعاء، نقل ق25، تغيّر الوقت…) أو تجاوز المدة: تحديث فوري.
      if (ref.read(authProvider).status == AuthStatus.signedIn &&
          ref.exists(barberRepoProvider) &&
          (m.kind.affectsQueue || m.kind == NotificationKind.overrun)) {
        ref.read(barberRepoProvider).refresh();
      }
    });
    final auth = ref.read(authProvider);
    _router = buildRouter(auth);
    if (auth.status == AuthStatus.unknown) auth.bootstrap();
  }

  @override
  void dispose() {
    _push?.cancel();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(prefsProvider);
    return MaterialApp.router(
      title: AppConfig.appLabel,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: SaloniTheme.light(),
      darkTheme: SaloniTheme.dark(),
      themeMode: prefs.themeMode,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: _router,
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('صالوني', style: SaloniTextStyles.display.copyWith(color: c.primary)),
            Text('الطاقم', style: SaloniTextStyles.body.copyWith(color: c.inkMuted)),
          ],
        ),
      ),
    );
  }
}

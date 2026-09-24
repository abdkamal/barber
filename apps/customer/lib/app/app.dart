import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saloni_ui/saloni_ui.dart' as ui;

import '../providers/session_controller.dart';
import '../providers/theme_provider.dart';
import '../services/notification_service.dart';
import '../screens/about_salon_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/home/home_shell.dart';
import '../screens/pending_approval_screen.dart';
import '../screens/salon_entry_screen.dart';
import '../screens/splash_screen.dart';

/// جذر التطبيق — يبني `MaterialApp` بالسمة والاتجاه RTL، ويحوّل بين الشاشات
/// وفق حالة الجلسة (`SessionController`).
class SaloniCustomerApp extends ConsumerWidget {
  const SaloniCustomerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'صالوني',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ui.SaloniTheme.light(),
      darkTheme: ui.SaloniTheme.dark(),
      themeMode: themeMode,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _RootSwitcher(),
    );
  }
}

class _RootSwitcher extends ConsumerStatefulWidget {
  const _RootSwitcher();

  @override
  ConsumerState<_RootSwitcher> createState() => _RootSwitcherState();
}

/// تدفّق ما قبل الدخول (رمز الصالون ← حول الصالون ← تسجيل/دخول) يُدار محليًا
/// بمكدّس Navigator بسيط داخل هذه الحاوية، بينما التبديل بين «بانتظار
/// الاعتماد» و«الرئيسية» يتبع حالة الجلسة مباشرة.
class _RootSwitcherState extends ConsumerState<_RootSwitcher> {
  final _preAuthNavigatorKey = GlobalKey<NavigatorState>();
  NotificationService? _notifications;
  NotificationReadiness? _readiness;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);

    switch (session.status) {
      case SessionStatus.loading:
        return const SplashScreen();
      case SessionStatus.error:
        return Scaffold(
          body: Center(
            child: ui.EmptyState(
              icon: ui.SaloniIconName.warning,
              title: 'تعذّر الاتصال بالسيرفر',
              body: session.errorMessage,
              action: ui.SaloniButton(
                label: 'إعادة المحاولة',
                onPressed: () => ref.read(sessionControllerProvider.notifier).retry(),
              ),
            ),
          ),
        );
      case SessionStatus.needsSalon:
        return Navigator(
          key: _preAuthNavigatorKey,
          onGenerateRoute: (settings) => MaterialPageRoute(
            builder: (_) => SalonEntryScreen(
              onSubmit: (code) => _openAbout(context, code),
            ),
          ),
        );
      case SessionStatus.pendingApproval:
        return PendingApprovalScreen(
          onRetry: () => ref.read(sessionControllerProvider.notifier).retry(),
          onLogout: () => ref.read(sessionControllerProvider.notifier).logoutActive(),
        );
      case SessionStatus.ready:
        _ensureNotifications();
        return HomeShell(
          api: session.api!,
          salonCode: session.activeCode!,
          salonName: session.activeName ?? session.activeCode!,
          currency: 'ر.س',
          savedSalons: session.savedSalons,
          isDark: Theme.of(context).brightness == Brightness.dark,
          notificationReadiness: _readiness,
          fcmMessages: _notifications?.onMessage,
          onToggleTheme: () => ref.read(themeModeProvider.notifier).toggle(),
          onSwitchSalon: (code) => ref.read(sessionControllerProvider.notifier).switchSalon(code),
          onAddSalon: () => ref.read(sessionControllerProvider.notifier).addAnotherSalon(),
          onRemoveSalon: (code) => ref.read(sessionControllerProvider.notifier).removeSalon(code),
          onLogout: () => ref.read(sessionControllerProvider.notifier).logoutActive(),
        );
    }
  }

  void _ensureNotifications() {
    final customerApi = ref.read(sessionControllerProvider).api;
    if (customerApi == null || _notifications != null) return;
    _notifications = NotificationService(customerApi);
    _notifications!.initializeAndRegister().then((r) {
      if (mounted) setState(() => _readiness = r);
    });
  }

  void _openAbout(BuildContext context, String code) {
    _preAuthNavigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => AboutSalonScreen(
          api: ref.read(sessionControllerProvider.notifier).anonymousApi(),
          salonCode: code,
          onContinue: () => _openRegister(code),
        ),
      ),
    );
  }

  void _openRegister(String code) {
    _preAuthNavigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => RegisterScreen(
          salonName: code,
          onSubmit: ({required name, required phone, required password, required rememberMe}) =>
              ref.read(sessionControllerProvider.notifier).registerAndActivate(
                    salonCode: code,
                    name: name,
                    phone: phone,
                    password: password,
                    rememberMe: rememberMe,
                  ),
          onGoLogin: () => _openLogin(code),
        ),
      ),
    );
  }

  void _openLogin(String code) {
    _preAuthNavigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          salonName: code,
          onSubmit: ({required phone, required password, required rememberMe}) =>
              ref.read(sessionControllerProvider.notifier).loginAndActivate(
                    salonCode: code,
                    salonName: code,
                    phone: phone,
                    password: password,
                    rememberMe: rememberMe,
                  ),
        ),
      ),
    );
  }
}

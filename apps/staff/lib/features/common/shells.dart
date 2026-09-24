import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saloni_ui/saloni_ui.dart';

import '../../core/format.dart';
import '../../data/barber_repository.dart';
import '../../state/app_services.dart';
import 'first_run.dart';
import 'ui.dart';

/// شريط الاتصال الدائم (design.md §10) — مربوط بحالة المستودع.
class LiveConnectionBar extends ConsumerWidget {
  const LiveConnectionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(barberRepoProvider);
    final state = switch (repo.link) {
      LinkStatus.online => SaloniConnectionState.online,
      LinkStatus.syncing => SaloniConnectionState.syncing,
      LinkStatus.offline => SaloniConnectionState.offline,
    };
    return ConnectionBar(
      state: state,
      pending: repo.pending,
      since: repo.offlineSince == null ? null : hhmm(repo.offlineSince!),
    );
  }
}

/// هيكل الحلاق: شريط الاتصال أعلى كل شاشة + الشريط السفلي (navStaff).
class BarberShell extends ConsumerWidget {
  const BarberShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(barberRepoProvider);
    final awaiting = repo.awaitingPayments;
    return FirstRunGate(
      role: 'barber',
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const LiveConnectionBar(),
              Expanded(child: shell),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: SaloniBottomNav(
            active: shell.currentIndex,
            onTap: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
            items: [
              const SaloniNavItem(icon: SaloniIconName.listNumbers, label: 'طابوري'),
              SaloniNavItem(
                icon: SaloniIconName.coins,
                label: 'الدفعات',
                badge: awaiting > 0 ? awaiting : null,
              ),
              const SaloniNavItem(icon: SaloniIconName.coffee, label: 'استراحاتي'),
              const SaloniNavItem(icon: SaloniIconName.gearSix, label: 'المزيد'),
            ],
          ),
        ),
      ),
    );
  }
}

/// هيكل المدير (navManager).
class ManagerShell extends ConsumerStatefulWidget {
  const ManagerShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  ConsumerState<ManagerShell> createState() => _ManagerShellState();
}

class _ManagerShellState extends ConsumerState<ManagerShell> {
  @override
  void initState() {
    super.initState();
    // هل فُعّل الصالون منذ آخر دخول؟ (ق37)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = ref.read(authProvider);
      if (auth.salon?.pendingActivation ?? true) auth.refreshSessionInfo();
    });
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    return FirstRunGate(
      role: 'manager',
      child: Scaffold(
        body: SafeArea(bottom: false, child: shell),
        bottomNavigationBar: SafeArea(
          top: false,
          child: SaloniBottomNav(
            active: shell.currentIndex,
            onTap: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
            items: const [
              SaloniNavItem(icon: SaloniIconName.listNumbers, label: 'الطوابير'),
              SaloniNavItem(icon: SaloniIconName.chartBar, label: 'التقارير'),
              SaloniNavItem(icon: SaloniIconName.storefront, label: 'الصالون'),
              SaloniNavItem(icon: SaloniIconName.gearSix, label: 'الإعدادات'),
            ],
          ),
        ),
      ),
    );
  }
}

/// شاشة مستقلة (خارج الهيكل) بعنوان وزر رجوع.
class DetailScaffold extends StatelessWidget {
  const DetailScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    this.bottom,
    this.showConnection = false,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final Widget? bottom;
  final bool showConnection;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showConnection) const LiveConnectionBar(),
            _Header(title: title, subtitle: subtitle),
            Expanded(child: body),
            if (bottom != null) bottom!,
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final canPop = GoRouter.of(context).canPop();
    return PageHeader(
      title: title,
      subtitle: subtitle,
      onBack: () => canPop ? context.pop() : context.go('/splash'),
    );
  }
}

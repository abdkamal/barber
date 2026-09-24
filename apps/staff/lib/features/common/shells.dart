import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saloni_ui/saloni_ui.dart';

import '../../core/format.dart';
import '../../data/barber_repository.dart';
import '../../state/app_services.dart';
import 'first_run.dart';
import 'salon_qr.dart';
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

/// الشريط العلوي الدائم للتطبيق (المرحلة 11): اسم الصالون وزر QR الصالون،
/// ومعهما — للمدير في «وضع الحلاق» — زر رجوع واضح إلى لوحة المدير.
class ShellTopBar extends ConsumerWidget {
  const ShellTopBar({super.key, this.onBack, this.backLabel});

  /// رجوع (مثلًا إلى لوحة المدير)؛ `null` = لا زر رجوع.
  final VoidCallback? onBack;
  final String? backLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final c = context.saloniColors;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
          SaloniSpacing.space4, SaloniSpacing.space2, SaloniSpacing.space4, 0),
      child: Row(
        children: [
          if (onBack != null) ...[
            Semantics(
              button: true,
              label: 'رجوع إلى ${backLabel ?? 'الرئيسية'}',
              child: Material(
                color: c.surfaceRaised,
                shape: RoundedRectangleBorder(
                    borderRadius: SaloniRadius.mdAll, side: BorderSide(color: c.line)),
                child: InkWell(
                  key: const Key('shell-back'),
                  borderRadius: SaloniRadius.mdAll,
                  onTap: onBack,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 14, 0),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        // الرجوع في RTL يشير إلى اليمين.
                        SaloniIcon(SaloniIconName.caretRight, color: c.ink, mirrorInRtl: false),
                        const SizedBox(width: 6),
                        Text(backLabel ?? 'رجوع',
                            style: SaloniTextStyles.label.copyWith(color: c.ink)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: SaloniSpacing.space3),
          ],
          Expanded(
            child: Text(
              auth.salon?.name ?? 'صالوني',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SaloniTextStyles.caption.copyWith(color: c.inkMuted),
            ),
          ),
          const SizedBox(width: SaloniSpacing.space3),
          const SalonQrButton(),
        ],
      ),
    );
  }
}

/// زر الرجوع في أندرويد داخل هيكل التبويبات (المرحلة 11). التبويب نفسه
/// صفحة وحيدة في فرعه فلا يستشيره go_router؛ لذا يُعالج الرجوع هنا على مستوى
/// الهيكل: من تبويب غير الأول إلى الأول، ومن الأول إلى [homeBack] إن وُجد
/// (لوحة المدير لمن في «وضع الحلاق»)، وإلا السلوك العادي (الخروج).
class ShellBackScope extends StatelessWidget {
  const ShellBackScope({super.key, required this.shell, this.homeBack, required this.child});
  final StatefulNavigationShell shell;
  final String? homeBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final onFirstTab = shell.currentIndex == 0;
    return PopScope(
      canPop: onFirstTab && homeBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!onFirstTab) {
          shell.goBranch(0);
        } else if (homeBack != null) {
          GoRouter.of(context).go(homeBack!);
        }
      },
      child: child,
    );
  }
}

/// هيكل الحلاق: شريط الاتصال والشريط العلوي أعلى كل شاشة + الشريط السفلي
/// (navStaff). للمدير الذي يحلق أيضًا («وضع الحلاق») رجوع دائم إلى لوحته.
class BarberShell extends ConsumerWidget {
  const BarberShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(barberRepoProvider);
    final isManager = ref.watch(authProvider).isManager;
    final awaiting = repo.awaitingPayments;
    return FirstRunGate(
      role: 'barber',
      child: ShellBackScope(
        shell: shell,
        homeBack: isManager ? '/m/queues' : null,
        child: Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                const LiveConnectionBar(),
                ShellTopBar(
                  onBack: isManager ? () => context.go('/m/queues') : null,
                  backLabel: isManager ? 'لوحة المدير' : null,
                ),
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
      child: ShellBackScope(
        shell: shell,
        child: Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(children: [
              const ShellTopBar(),
              Expanded(child: shell),
            ]),
          ),
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
      ),
    );
  }
}

/// وجهة الرجوع لشاشة مستقلة فُتحت دون مكدّس (رابط مباشر أو `go`): شاشات
/// الإدارة ترجع إلى الإعدادات، وشاشات الحلاق إلى «طابوري».
String detailFallback(String location) {
  if (location.startsWith('/b/')) return '/b/queue';
  if (location.startsWith('/m/')) return '/m/settings';
  return '/splash';
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
    return PageHeader(
      title: title,
      subtitle: subtitle,
      onBack: () {
        final router = GoRouter.of(context);
        if (router.canPop()) {
          router.pop();
        } else {
          router.go(detailFallback(GoRouterState.of(context).matchedLocation));
        }
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saloni_ui/saloni_ui.dart';

import '../../state/app_services.dart';
import 'ui.dart';

/// هل الإشعارات مرفوضة على الجهاز؟ (ق31، design.md §8) — يعرض تحذيرًا دائمًا.
final notificationsDeniedProvider = StateProvider<bool>((ref) => false);

class _Tip {
  const _Tip(this.icon, this.title, this.body);
  final SaloniIconName icon;
  final String title;
  final String body;
}

const _barberTips = [
  _Tip(SaloniIconName.listNumbers, 'طابورك أمامك',
      'ابدأ خدمة الزبون وأنهِها بالزرين الكبيرين؛ الأوقات المتوقعة تتحدّث للزبائن تلقائيًا.'),
  _Tip(SaloniIconName.wifiSlash, 'يعمل دون إنترنت',
      'ما تسجّله أثناء الانقطاع يُحفظ على جهازك ويُزامن وحده عند عودة الاتصال. إضافة زبون حاضر فقط تحتاج اتصالًا.'),
  _Tip(SaloniIconName.bellRinging, 'الزبون المتأخر',
      'اضغط «لم يصل؟» على المستدعى: التأجيل مرة واحدة، و«لم يحضر» يُتاح بعده.'),
];

const _managerTips = [
  _Tip(SaloniIconName.usersThree, 'طوابير كل الحلاقين',
      'تابع حالة كل حلاق، وانقل الحجوزات يدويًا عند غياب حلاق — يُبلَّغ الزبائن تلقائيًا.'),
  _Tip(SaloniIconName.storefront, 'ملف صالونك',
      'الاسم والصور والخدمات والمنتجات تظهر للزبائن في «حول الصالون».'),
  _Tip(SaloniIconName.chartBar, 'التقارير والمعلّقات',
      'الإيرادات والزيارات ودقة الأوقات، مع الدفعات والحسابات التي تنتظر قرارك.'),
];

/// جولة تعريفية قصيرة عند أول تشغيل (مبدأ السياسة 11) + فحص الإشعارات (ق31).
class FirstRunGate extends ConsumerStatefulWidget {
  const FirstRunGate({super.key, required this.role, required this.child});
  final String role;
  final Widget child;

  @override
  ConsumerState<FirstRunGate> createState() => _FirstRunGateState();
}

class _FirstRunGateState extends ConsumerState<FirstRunGate> {
  static final Set<String> _doneThisRun = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (!mounted || _doneThisRun.contains(widget.role)) return;
    _doneThisRun.add(widget.role);
    final prefs = ref.read(prefsProvider);
    if (!prefs.onboardingSeen(widget.role)) {
      await showOnboarding(context, widget.role);
      await prefs.setOnboardingSeen(widget.role, true);
    }
    if (!mounted) return;
    await _checkNotifications();
  }

  Future<void> _checkNotifications() async {
    final services = ref.read(servicesProvider);
    var allowed = await services.device.notificationsAllowed();
    if (allowed == false && !services.prefs.notificationCheckDone) {
      allowed = await services.device.requestNotifications();
      await services.prefs.setNotificationCheckDone();
      if (widget.role == 'barber') await services.device.requestBatteryExemption();
    }
    if (!mounted) return;
    ref.read(notificationsDeniedProvider.notifier).state = allowed == false;
    if (allowed == false) {
      await showSaloniSheet<void>(context, (ctx) => const _NotificationWarning());
    }
    services.push
        .register(services.api, notificationsAllowed: allowed ?? true)
        .ignore();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _NotificationWarning extends StatelessWidget {
  const _NotificationWarning();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SaloniBanner(
          tone: SaloniBannerTone.warning,
          title: 'الإشعارات متوقفة على هذا الجهاز',
          body: 'لن يصلك تنبيه تجاوز مدة الخدمة ولا تنبيهات الصالون، وقد يوقف أندرويد '
              'مزامنة طابورك في الخلفية. فعّل إشعارات «صالوني — الطاقم» من إعدادات الهاتف.',
        ),
        const SizedBox(height: 16),
        SaloniButton(
          label: 'فهمت',
          block: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

Future<void> showOnboarding(BuildContext context, String role) {
  final tips = role == 'manager' ? _managerTips : _barberTips;
  return showSaloniSheet<void>(context, (ctx) {
    final c = ctx.saloniColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('أهلًا بك في صالوني', style: SaloniTextStyles.title2.copyWith(color: c.ink)),
        const SizedBox(height: 4),
        const Muted('ثلاث نصائح سريعة قبل أن تبدأ'),
        const SizedBox(height: 16),
        for (final t in tips) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: c.primarySoft, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: SaloniIcon(t.icon, color: c.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, style: SaloniTextStyles.bodyStrong.copyWith(color: c.ink)),
                    Text(t.body, style: SaloniTextStyles.caption.copyWith(color: c.inkMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        const SizedBox(height: 6),
        SaloniButton(
          label: 'لنبدأ',
          size: SaloniButtonSize.lg,
          block: true,
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ],
    );
  });
}

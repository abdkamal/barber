import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saloni_api/saloni_api.dart' as sa;
import 'package:saloni_ui/saloni_ui.dart';

import '../../core/format.dart';
import '../../state/app_services.dart';
import '../common/ui.dart';

String breakKindAr(sa.BreakKind k) => switch (k) {
      sa.BreakKind.rest => 'راحة',
      sa.BreakKind.prayer => 'صلاة',
      sa.BreakKind.emergency => 'طارئة',
    };

/// استراحاتي: الاستراحات المجدولة، الاستراحة الطارئة، «لن أعمل اليوم» (ق26).
class BreaksScreen extends ConsumerWidget {
  const BreaksScreen({super.key});

  Future<void> _absent(BuildContext context, WidgetRef ref) async {
    final reason = TextEditingController();
    final ok = await showSaloniSheet<bool>(context, (ctx) {
      final c = ctx.saloniColors;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('لن أعمل اليوم', style: SaloniTextStyles.title2.copyWith(color: c.ink)),
          const SizedBox(height: 8),
          Text(
            'يتوقف الحجز عندك اليوم، ويُنبَّه المدير لنقل حجوزاتك القائمة يدويًا. '
            'لا يُنقل أحد تلقائيًا.',
            style: SaloniTextStyles.body.copyWith(color: c.inkMuted),
          ),
          const SizedBox(height: 14),
          SaloniTextField(label: 'السبب (اختياري)', controller: reason),
          const SizedBox(height: 20),
          SaloniButton(
            key: const Key('absent-confirm'),
            label: 'تأكيد',
            variant: SaloniButtonVariant.danger,
            size: SaloniButtonSize.lg,
            block: true,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
          const SizedBox(height: 10),
          SaloniButton(
            label: 'تراجع',
            variant: SaloniButtonVariant.ghost,
            block: true,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
        ],
      );
    });
    if (ok == true) {
      await ref.read(barberRepoProvider).reportAbsentToday(reason.text.trim());
      if (context.mounted) toast(context, 'أُبلغ المدير أنك لن تعمل اليوم');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(barberRepoProvider);
    final c = context.saloniColors;
    final now = DateTime.now();
    final active = repo.activeBreak;
    final breaks = [...repo.breaks]..sort((a, b) => a.start.compareTo(b.start));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(title: 'استراحاتي', subtitle: 'اليوم'),
        Expanded(
          child: PageBody(onRefresh: repo.refresh, children: [
            if (active != null)
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StatusBadge(
                      status: BookingStatus.waiting,
                      label: 'استراحة ${breakKindAr(active.kind)} منذ ${timeAr(active.since)}',
                      tone: SaloniTone.steel,
                    ),
                    const SizedBox(height: 12),
                    SaloniButton(
                      key: const Key('end-break'),
                      label: 'إنهاء الاستراحة',
                      icon: SaloniIconName.check,
                      size: SaloniButtonSize.lg,
                      block: true,
                      onPressed: repo.endBreak,
                    ),
                  ],
                ),
              )
            else
              SaloniButton(
                key: const Key('emergency-break'),
                label: 'استراحة طارئة الآن',
                icon: SaloniIconName.coffee,
                size: SaloniButtonSize.lg,
                variant: SaloniButtonVariant.secondary,
                block: true,
                onPressed: () => repo.startBreak(sa.BreakKind.emergency),
              ),
            if (active == null)
              const Muted('سجّلها عند الحاجة المفاجئة؛ تُحدَّث أوقات زبائنك تلقائيًا.'),
            Section(title: 'استراحات اليوم', children: [
              if (breaks.isEmpty) const Muted('لا استراحات مجدولة اليوم.'),
              for (final b in breaks)
                SurfaceCard(
                  child: Row(
                    children: [
                      SaloniIcon(
                        b.kind == sa.BreakKind.prayer ? SaloniIconName.clock : SaloniIconName.coffee,
                        color: c.inkMuted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(breakKindAr(b.kind),
                            style: SaloniTextStyles.bodyStrong.copyWith(color: c.ink)),
                      ),
                      Text('${timeAr(b.start)} – ${timeAr(b.end)}',
                          style: SaloniTextStyles.body.copyWith(color: c.inkMuted)),
                      if (active == null &&
                          !now.isBefore(b.start.subtract(const Duration(minutes: 15))) &&
                          now.isBefore(b.end)) ...[
                        const SizedBox(width: 8),
                        SaloniButton(
                          label: 'ابدأ',
                          size: SaloniButtonSize.sm,
                          variant: SaloniButtonVariant.secondary,
                          onPressed: () => repo.startBreak(b.kind),
                        ),
                      ],
                    ],
                  ),
                ),
            ]),
            if (repo.walkInOnly.isNotEmpty)
              Section(title: 'فترات الحاضرين فقط', children: [
                const Muted('لا تُقبل فيها حجوزات التطبيق؛ أضف فيها زبائن حاضرين.'),
                for (final w in repo.walkInOnly)
                  SurfaceCard(
                    child: Row(children: [
                      SaloniIcon(SaloniIconName.userPlus, color: c.inkMuted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('حاضرون فقط', style: SaloniTextStyles.bodyStrong.copyWith(color: c.ink)),
                      ),
                      Text('${timeAr(w.start)} – ${timeAr(w.end)}',
                          style: SaloniTextStyles.body.copyWith(color: c.inkMuted)),
                    ]),
                  ),
              ]),
            Section(title: 'اليوم كله', children: [
              repo.absentToday
                  ? const SaloniBanner(
                      tone: SaloniBannerTone.info,
                      title: 'أبلغت أنك لن تعمل اليوم',
                      body: 'للتراجع تواصل مع مدير الصالون.',
                    )
                  : SaloniButton(
                      key: const Key('absent-today'),
                      label: 'لن أعمل اليوم',
                      variant: SaloniButtonVariant.danger,
                      block: true,
                      onPressed: () => _absent(context, ref),
                    ),
            ]),
          ]),
        ),
      ],
    );
  }
}

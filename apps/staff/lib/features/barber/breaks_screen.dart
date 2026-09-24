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
      sa.BreakKind.walkInOnly => 'حاضرون فقط',
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
          Text('لن تعمل اليوم؟', style: SaloniTextStyles.title2.copyWith(color: c.ink)),
          const SizedBox(height: 8),
          Text(
            'يتوقف الحجز عندك اليوم فورًا، ويُنبَّه المدير لنقل حجوزاتك القائمة يدويًا '
            '(لا يُنقل أحد تلقائيًا). تستطيع التراجع اليوم نفسه من هذه الشاشة.',
            style: SaloniTextStyles.body.copyWith(color: c.inkMuted),
          ),
          const SizedBox(height: 14),
          SaloniTextField(label: 'السبب (اختياري)', controller: reason),
          const SizedBox(height: 20),
          SaloniButton(
            key: const Key('absent-confirm'),
            label: 'نعم، لن أعمل اليوم',
            variant: SaloniButtonVariant.danger,
            size: SaloniButtonSize.lg,
            block: true,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
          const SizedBox(height: 10),
          SaloniButton(
            key: const Key('absent-cancel'),
            label: 'تراجع',
            variant: SaloniButtonVariant.ghost,
            block: true,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
        ],
      );
    });
    if (ok != true || !context.mounted) return;
    final repo = ref.read(barberRepoProvider);
    try {
      // متفائل: تتغير الشاشة فورًا ويُرسل الحدث عند توفر الاتصال.
      await repo.reportAbsentToday(reason.text.trim());
      if (context.mounted) {
        toast(
          context,
          repo.isOnline
              ? 'سُجّل أنك لن تعمل اليوم — توقف الحجز عندك وأُبلغ المدير'
              : 'سُجّل أنك لن تعمل اليوم — يُرسل للمدير عند عودة الاتصال',
        );
      }
    } catch (e) {
      if (context.mounted) toast(context, 'تعذّر التسجيل: ${errorText(e)}');
    }
  }

  Future<void> _undoAbsent(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'ستعمل اليوم؟',
      body: 'يعود يومك إلى وضعه الطبيعي ويُستأنف الحجز عندك من الآن. '
          'الحجوزات التي نقلها المدير إلى حلاق آخر أثناء غيابك تبقى حيث هي ولا تعود تلقائيًا.',
      confirm: 'نعم، سأعمل اليوم',
    );
    if (!ok || !context.mounted) return;
    final repo = ref.read(barberRepoProvider);
    try {
      await repo.cancelAbsentToday();
      if (context.mounted) {
        toast(
          context,
          repo.isOnline
              ? 'عدت للعمل اليوم — استُؤنف الحجز عندك'
              : 'عدت للعمل اليوم — يُرسل التراجع عند عودة الاتصال',
        );
      }
    } catch (e) {
      if (context.mounted) toast(context, 'تعذّر التراجع: ${errorText(e)}');
    }
  }

  Future<void> _startBreak(BuildContext context, WidgetRef ref, sa.BreakKind kind) async {
    try {
      await ref.read(barberRepoProvider).startBreak(kind);
    } catch (e) {
      if (context.mounted) toast(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(barberRepoProvider);
    final isManager = ref.watch(authProvider).isManager;
    final c = context.saloniColors;
    final now = DateTime.now();
    final absent = repo.absentToday;
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
                // ق26: لا استراحة في يوم «لن أعمل اليوم».
                onPressed: absent ? null : () => _startBreak(context, ref, sa.BreakKind.emergency),
              ),
            if (active == null)
              Muted(absent
                  ? 'غير متاحة لأنك أبلغت أنك لن تعمل اليوم. تراجع عن ذلك أولًا إن كنت ستعمل.'
                  : 'سجّلها عند الحاجة المفاجئة؛ تُحدَّث أوقات زبائنك تلقائيًا.'),
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
                          !absent &&
                          !now.isBefore(b.start.subtract(const Duration(minutes: 15))) &&
                          now.isBefore(b.end)) ...[
                        const SizedBox(width: 8),
                        SaloniButton(
                          label: 'ابدأ',
                          size: SaloniButtonSize.sm,
                          variant: SaloniButtonVariant.secondary,
                          onPressed: () => _startBreak(context, ref, b.kind),
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
              if (!absent)
                SaloniButton(
                  key: const Key('absent-today'),
                  label: 'لن أعمل اليوم',
                  variant: SaloniButtonVariant.danger,
                  block: true,
                  onPressed: () => _absent(context, ref),
                )
              else ...[
                SaloniBanner(
                  key: const Key('absent-banner'),
                  tone: SaloniBannerTone.warning,
                  title: repo.absenceRecordedBySelf == false
                      ? 'سجّل المدير أنك لن تعمل اليوم'
                      : 'أبلغت أنك لن تعمل اليوم',
                  body: [
                    'الحجز متوقف عندك اليوم.',
                    if (repo.absenceReason != null) 'السبب: ${repo.absenceReason}.',
                    if (!repo.isOnline && repo.pending > 0) 'يُرسل عند عودة الاتصال.',
                  ].join(' '),
                ),
                if (repo.canUndoAbsence(isManager: isManager))
                  SaloniButton(
                    key: const Key('absent-undo'),
                    label: 'تراجع — سأعمل اليوم',
                    icon: SaloniIconName.arrowUUpLeft,
                    variant: SaloniButtonVariant.secondary,
                    block: true,
                    onPressed: () => _undoAbsent(context, ref),
                  )
                else
                  const Muted('سجّل المدير غيابك؛ للتراجع تواصل مع مدير الصالون.'),
              ],
            ]),
          ]),
        ),
      ],
    );
  }
}

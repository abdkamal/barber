import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saloni_api/saloni_api.dart' as sa;
import 'package:saloni_ui/saloni_ui.dart';

import '../../core/format.dart';
import '../../data/barber_repository.dart';
import '../../data/models.dart';
import '../../state/app_services.dart';
import '../common/first_run.dart';
import '../common/ui.dart';
import 'closing_sheet.dart';
import 'edit_services_sheet.dart';
import 'late_sheet.dart';
import 'payment_sheet.dart';

BookingStatus uiStatus(sa.BookingStatus s) => switch (s) {
      sa.BookingStatus.waiting => BookingStatus.waiting,
      sa.BookingStatus.called => BookingStatus.called,
      sa.BookingStatus.inService => BookingStatus.inService,
      sa.BookingStatus.done => BookingStatus.done,
      sa.BookingStatus.cancelled => BookingStatus.cancelled,
      sa.BookingStatus.noShow => BookingStatus.noShow,
      sa.BookingStatus.offered => BookingStatus.offered,
    };

/// «طابوري» (S-Queue / S-Offline).
class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // عداد الخدمة الجارية وتنبيه تجاوز المدة (ق27).
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final over = ref.read(barberRepoProvider).checkOverrun();
    if (over != null) {
      HapticFeedback.heavyImpact();
      toast(context, 'تجاوزت خدمة ${over.name} مدتها المقدرة — لا تنسَ الضغط على «إنهاء»');
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _start(QueueEntry e) async {
    await ref.read(barberRepoProvider).startService(e.id);
  }

  Future<void> _end(QueueEntry e) async {
    final repo = ref.read(barberRepoProvider);
    await repo.finishService(e.id);
    if (!mounted) return;
    await showPaymentSheet(context, repo, e.id, e.name, e.priceCents,
        serviceNames(e.serviceIds, repo.services));
  }

  Future<void> _itemActions(QueueEntry e) async {
    final repo = ref.read(barberRepoProvider);
    final canStart = repo.current == null;
    await showSaloniSheet<void>(context, (ctx) {
      final c = ctx.saloniColors;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            SaloniAvatar(name: e.name, size: 45),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.name, style: SaloniTextStyles.title2.copyWith(color: c.ink)),
                Text(
                  '${serviceNames(e.serviceIds, repo.services)} · موعده المتوقع ${timeAr(e.eta)}',
                  style: SaloniTextStyles.caption.copyWith(color: c.inkMuted),
                ),
              ]),
            ),
          ]),
          if (e.phone != null) ...[
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(e.phone!,
                  textAlign: TextAlign.end,
                  style: SaloniTextStyles.body.copyWith(color: c.inkMuted)),
            ),
          ],
          const SizedBox(height: 16),
          SaloniButton(
            label: canStart ? 'بدء الخدمة — الزبون حاضر' : 'أنهِ الخدمة الجارية أولًا',
            icon: SaloniIconName.scissors,
            size: SaloniButtonSize.lg,
            block: true,
            onPressed: canStart
                ? () {
                    Navigator.of(ctx).pop();
                    _start(e);
                  }
                : null,
          ),
          if (e.status == sa.BookingStatus.called) ...[
            const SizedBox(height: 10),
            SaloniButton(
              label: 'لم يصل بعد؟',
              variant: SaloniButtonVariant.secondary,
              block: true,
              onPressed: () {
                Navigator.of(ctx).pop();
                showLateSheet(context, repo, e);
              },
            ),
          ],
          if (e.status == sa.BookingStatus.waiting &&
              e.id == repo.upcoming.firstOrNull?.id &&
              repo.called == null) ...[
            const SizedBox(height: 8),
            const Muted('يُستدعى الزبون تلقائيًا عندما يقترب دوره.', center: true),
          ],
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(barberRepoProvider);
    final auth = ref.watch(authProvider);
    final denied = ref.watch(notificationsDeniedProvider);
    final c = context.saloniColors;
    final now = DateTime.now();
    final current = repo.current;
    final upcoming = repo.upcoming;
    final awaiting = repo.awaitingPayments;
    final offline = repo.link == LinkStatus.offline;

    final children = <Widget>[];

    if (!repo.ready) {
      children.add(const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())));
    }
    if (denied) {
      children.add(const SaloniBanner(
        tone: SaloniBannerTone.warning,
        title: 'الإشعارات متوقفة',
        body: 'لن يصلك تنبيه تجاوز المدة، وقد تتوقف المزامنة في الخلفية. فعّلها من إعدادات الهاتف.',
      ));
    }
    if (repo.loadError != null) {
      children.add(SaloniBanner(tone: SaloniBannerTone.danger, body: repo.loadError));
    }
    if (repo.noShiftToday && !repo.absentToday) {
      children.add(const SaloniBanner(
        tone: SaloniBannerTone.info,
        title: 'لا دوام لك اليوم',
        body: 'لا يُحجز عندك اليوم وفق جدول الدوام. راجع المدير إن كان هذا غير صحيح.',
      ));
    }
    if (repo.absentToday) {
      children.add(const SaloniBanner(
        tone: SaloniBannerTone.info,
        title: 'أبلغت أنك لن تعمل اليوم',
        body: 'توقف الحجز عندك، ويُنبَّه المدير لنقل حجوزاتك القائمة.',
      ));
    }
    if (repo.activeBreak != null) {
      children.add(SaloniBanner(
        tone: SaloniBannerTone.info,
        title: 'أنت في استراحة منذ ${timeAr(repo.activeBreak!.since)}',
        action: SaloniButton(
          label: 'إنهاء الاستراحة',
          size: SaloniButtonSize.sm,
          variant: SaloniButtonVariant.secondary,
          onPressed: repo.endBreak,
        ),
      ));
    }
    if (offline) {
      children.add(repo.remoteBookingPaused
          ? const SaloniBanner(
              tone: SaloniBannerTone.warning,
              title: 'الحجز عن بعد متوقف عندك',
              body: 'عملك المحجوز أقل من ساعتين، فأوقفنا الحجوزات الجديدة حتى يعود الاتصال. '
                  'ما تسجله الآن يُحفظ ويُزامن تلقائيًا.',
            )
          : SaloniBanner(
              tone: SaloniBannerTone.warning,
              title: 'تستمر الحجوزات في آخر طابورك مؤقتًا',
              body: 'حتى ${timeAr(repo.offlineSince!.add(Duration(minutes: repo.maxDisconnectMinutes)))} '
                  'إن لم يعد الاتصال. ما تسجله الآن يُحفظ ويُزامن تلقائيًا.',
            ));
    }
    final closing = repo.closingDecisionsNeeded;
    if (closing.isNotEmpty) {
      children.add(SaloniBanner(
        tone: SaloniBannerTone.danger,
        title: 'حجوزات ستتجاوز وقت الإغلاق',
        body: '${closing.map((e) => e.name).join('، ')} — قرّر لكل منهم.',
        action: SaloniButton(
          label: 'اتخاذ القرار',
          size: SaloniButtonSize.sm,
          variant: SaloniButtonVariant.secondary,
          onPressed: () => showClosingSheet(context, repo, closing),
        ),
      ));
    }

    if (current != null) {
      final elapsed = current.actualStart == null
          ? 0
          : now.difference(current.actualStart!).inMinutes.clamp(0, 24 * 60);
      children.add(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CurrentServiceCard(
            key: const Key('current-card'),
            customer: current.name,
            services: serviceNames(current.serviceIds, repo.services),
            startedAt: current.actualStart == null ? '—' : timeAr(current.actualStart!),
            elapsed: elapsed,
            estimate: current.durationMin,
            onEnd: () => _end(current),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            children: [
              _TextLink(
                'تعديل الخدمة',
                onTap: () => showEditServicesSheet(context, repo, current),
              ),
              Text('·', style: TextStyle(color: c.lineStrong)),
              _TextLink('بعد الإنهاء: تأكيد الدفع', onTap: () => context.go('/b/payments')),
            ],
          ),
        ],
      ));
    } else if (upcoming.isNotEmpty) {
      final next = upcoming.first;
      children.add(SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              StatusBadge(status: uiStatus(next.status)),
              const Spacer(),
              Text('التالي', style: SaloniTextStyles.caption.copyWith(color: c.inkMuted)),
            ]),
            const SizedBox(height: 8),
            Text(next.name, style: SaloniTextStyles.title2.copyWith(color: c.ink)),
            Text(serviceNames(next.serviceIds, repo.services),
                style: SaloniTextStyles.body.copyWith(color: c.inkMuted)),
            const SizedBox(height: 12),
            SaloniButton(
              key: const Key('start-next'),
              label: 'بدء الخدمة',
              icon: SaloniIconName.scissors,
              size: SaloniButtonSize.lg,
              block: true,
              onPressed: () => _start(next),
            ),
            if (next.status == sa.BookingStatus.called) ...[
              const SizedBox(height: 10),
              SaloniButton(
                label: 'لم يصل بعد؟',
                variant: SaloniButtonVariant.secondary,
                block: true,
                onPressed: () => showLateSheet(context, repo, next),
              ),
            ],
          ],
        ),
      ));
    }

    children.add(Section(
      title: 'التالون',
      trailing: SaloniButton(
        key: const Key('walkin-button'),
        label: 'زبون حاضر',
        icon: SaloniIconName.userPlus,
        size: SaloniButtonSize.sm,
        variant: SaloniButtonVariant.secondary,
        onPressed: offline ? null : () => context.push('/b/walkin'),
      ),
      children: [
        if (offline) const Muted('إضافة زبون حاضر تحتاج اتصالًا بالإنترنت.'),
        if (upcoming.isEmpty && repo.ready)
          const EmptyState(
            icon: SaloniIconName.coffee,
            title: 'لا أحد في طابورك الآن',
            body: 'تظهر هنا الحجوزات الجديدة تلقائيًا.',
          ),
        for (var i = 0; i < upcoming.length; i++)
          InkWell(
            key: Key('queue-item-${upcoming[i].id}'),
            borderRadius: SaloniRadius.lgAll,
            onTap: () => _itemActions(upcoming[i]),
            child: QueueItem(
              position: i + 1,
              name: upcoming[i].name,
              services: serviceNames(upcoming[i].serviceIds, repo.services),
              eta: hhmm(upcoming[i].eta),
              duration: minutesAr(upcoming[i].durationMin),
              status: uiStatus(upcoming[i].status),
              requested: upcoming[i].kind == sa.BookingKind.requested,
              requestedAt: upcoming[i].requestedAt == null ? null : hhmm(upcoming[i].requestedAt!),
              walkIn: upcoming[i].walkIn,
            ),
          ),
      ],
    ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'طابوري',
          subtitle: [
            if (auth.accountName != null) auth.accountName!,
            weekdayAr(now),
          ].join(' · '),
          trailing: awaiting > 0
              ? StatusBadge(
                  status: BookingStatus.payAwaiting,
                  small: true,
                  label: '${digits('$awaiting')} بانتظار الدفع',
                )
              : null,
        ),
        Expanded(child: PageBody(onRefresh: repo.refresh, children: children)),
      ],
    );
  }
}

class _TextLink extends StatelessWidget {
  const _TextLink(this.text, {required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          text,
          style: SaloniTextStyles.label.copyWith(
            color: context.saloniColors.primary,
            decoration: TextDecoration.underline,
            decorationColor: context.saloniColors.primary,
          ),
        ),
      ),
    );
  }
}

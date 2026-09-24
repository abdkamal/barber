import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saloni_api/saloni_api.dart' as sa;
import 'package:saloni_ui/saloni_ui.dart';

import '../../core/format.dart';
import '../../state/app_services.dart';
import '../common/shells.dart';
import '../common/ui.dart';

/// اسم عربي لنوع حدث الجهاز.
String eventTypeAr(String? type) => switch (type) {
      'service_started' => 'بدء خدمة',
      'service_finished' => 'إنهاء خدمة',
      'services_changed' => 'تعديل الخدمات',
      'payment_confirmed' => 'تأكيد دفع',
      'postponed' => 'تأجيل',
      'waited' => 'انتظار الزبون',
      'no_show' => 'لم يحضر',
      'closing_decision' => 'قرار عند الإغلاق',
      'break_started' => 'بدء استراحة',
      'break_ended' => 'انتهاء استراحة',
      'absent_today' => 'غائب اليوم',
      _ => type ?? 'إجراء',
    };

/// ق40: «إجراءات مستردة للمراجعة» — ما رفعه مدير من جهاز حساب موقوف (وقع قبل
/// الإيقاف فطُبّق)، حتى يعلّمه المدير «تمت المراجعة».
class RecoveredScreen extends ConsumerStatefulWidget {
  const RecoveredScreen({super.key});

  @override
  ConsumerState<RecoveredScreen> createState() => _RecoveredScreenState();
}

class _RecoveredScreenState extends ConsumerState<RecoveredScreen> {
  Key _reloadKey = UniqueKey();
  final Set<String> _busy = {};

  Future<void> _ack(sa.RecoveredEventItem item) async {
    setState(() => _busy.add(item.id));
    try {
      await ref.read(servicesProvider).api.acknowledgeRecoveredEvent(item.id);
      if (mounted) setState(() => _reloadKey = UniqueKey());
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.read(servicesProvider).api;
    return DetailScaffold(
      title: 'إجراءات مستردة للمراجعة',
      subtitle: 'رُفعت من أجهزة حسابات موقوفة (قبل الإيقاف فقط)',
      body: AsyncView<List<sa.RecoveredEventItem>>(
        key: _reloadKey,
        load: () => api.getRecoveredEvents(),
        builder: (context, list, reload) => PageBody(onRefresh: reload, gap: 10, children: [
          if (list.isEmpty)
            const EmptyState(
              icon: SaloniIconName.checkCircle,
              title: 'لا إجراءات بانتظار المراجعة',
              body: 'تظهر هنا الإجراءات التي رفعها مدير من جهاز حساب موقوف.',
            ),
          for (final item in list) _card(context, item),
        ]),
      ),
    );
  }

  Widget _card(BuildContext context, sa.RecoveredEventItem item) {
    final c = context.saloniColors;
    final at = item.occurredAt;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                [eventTypeAr(item.type), if (item.customerName != null) item.customerName!].join(' — '),
                style: SaloniTextStyles.bodyStrong.copyWith(color: c.ink),
              ),
            ),
            if (item.approximate)
              const StatusBadge(status: BookingStatus.waiting, small: true, label: 'توقيت تقريبي'),
          ]),
          const SizedBox(height: 4),
          Muted([
            'الحلاق: ${item.staffName ?? '—'}',
            if (at != null) 'وقع ${weekdayAr(at)} ${timeAr(at)}',
          ].join(' · ')),
          Muted([
            if (item.suspendedAt != null) 'أُوقف ${weekdayAr(item.suspendedAt!)} ${timeAr(item.suspendedAt!)}',
            if (item.recoveredByName != null) 'رفعه ${item.recoveredByName}',
          ].join(' · ')),
          const SizedBox(height: 10),
          SaloniButton(
            label: 'تمت المراجعة',
            icon: SaloniIconName.check,
            size: SaloniButtonSize.sm,
            variant: SaloniButtonVariant.secondary,
            loading: _busy.contains(item.id),
            onPressed: _busy.contains(item.id) ? null : () => _ack(item),
          ),
        ],
      ),
    );
  }
}

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
/// الإيقاف فطُبّق، أو بوقت غير مؤكد فلم يُطبّق ويُسجَّل يدويًا إن حدث)، وما وصل
/// بالمزامنة العادية بعد إعادة التفعيل وقد وقع أثناء الإيقاف — حتى يعلّمه
/// المدير «تمت المراجعة».
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
      subtitle: 'من أجهزة حسابات موقوفة، أو وقعت أثناء إيقاف الحساب',
      body: AsyncView<List<sa.RecoveredEventItem>>(
        key: _reloadKey,
        load: () => api.getRecoveredEvents(),
        builder: (context, list, reload) => PageBody(onRefresh: reload, gap: 10, children: [
          if (list.isEmpty)
            const EmptyState(
              icon: SaloniIconName.checkCircle,
              title: 'لا إجراءات بانتظار المراجعة',
              body: 'تظهر هنا الإجراءات التي رفعها مدير من جهاز حساب موقوف، '
                  'وما وقع أثناء إيقاف حساب ثم وصل بعد إعادة تفعيله.',
            ),
          for (final item in list) _card(context, item),
        ]),
      ),
    );
  }

  /// ملخص الحمولة ليسجّل المدير الإجراء يدويًا (المبلغ، عدد الخدمات…).
  String _payloadAr(sa.RecoveredEventItem item) {
    final p = item.payloadSummary;
    final cur = ref.read(authProvider).currency;
    return [
      if (p['amount'] is num) 'المبلغ: ${cur.format((p['amount'] as num).toInt())}',
      if (p['serviceIds'] is List) 'الخدمات: ${digits('${(p['serviceIds'] as List).length}')}',
      if (p['steps'] is num) 'التأجيل: ${digits('${p['steps']}')}',
      if (p['decision'] == 'serve_late') 'القرار: خدمة بعد الإغلاق',
      if (p['decision'] == 'cancel') 'القرار: إلغاء',
      if (p['durationMin'] is num) minutesAr((p['durationMin'] as num).toInt()),
      if (p['reason'] is String && (p['reason'] as String).isNotEmpty) 'السبب: ${p['reason']}',
    ].join(' · ');
  }

  Widget _card(BuildContext context, sa.RecoveredEventItem item) {
    final c = context.saloniColors;
    final at = item.occurredAt;
    final during = item.kind == sa.RecoveredEventKind.duringSuspension;
    final payload = _payloadAr(item);
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
            if (!item.applied)
              const StatusBadge(status: BookingStatus.cancelled, small: true, label: 'لم يُطبّق')
            else if (during)
              const StatusBadge(status: BookingStatus.waiting, small: true, label: 'أثناء الإيقاف')
            else if (item.approximate)
              const StatusBadge(status: BookingStatus.waiting, small: true, label: 'توقيت تقريبي'),
          ]),
          if (!item.applied) ...[
            const SizedBox(height: 4),
            Text(
              'لم يُطبّق لأن وقته تقريبي (أُعيد تشغيل الجهاز دون اتصال) فلا يُعرف أوقع قبل الإيقاف. '
              'سجّله يدويًا إن كان قد حدث فعلًا.',
              style: SaloniTextStyles.body.copyWith(color: c.ink),
            ),
          ],
          if (during) ...[
            const SizedBox(height: 4),
            Text(
              'وقع أثناء إيقاف الحساب ووصل بعد إعادة تفعيله — طُبّق، راجعه.',
              style: SaloniTextStyles.body.copyWith(color: c.ink),
            ),
          ],
          if (payload.isNotEmpty) Muted(payload),
          const SizedBox(height: 4),
          Muted([
            'الحلاق: ${item.staffName ?? '—'}',
            if (at != null) '${item.approximate ? 'وقت الجهاز' : 'وقع'} ${weekdayAr(at)} ${timeAr(at)}',
          ].join(' · ')),
          Muted([
            if (item.suspendedAt != null) 'أُوقف ${weekdayAr(item.suspendedAt!)} ${timeAr(item.suspendedAt!)}',
            if (item.reactivatedAt != null) 'أُعيد تفعيله ${weekdayAr(item.reactivatedAt!)} ${timeAr(item.reactivatedAt!)}',
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saloni_api/saloni_api.dart' as sa;
import 'package:saloni_ui/saloni_ui.dart';

import '../../core/format.dart';
import '../../state/app_services.dart';
import '../common/ui.dart';

/// الدفعات (S-Payments): بانتظار التأكيد / مؤكدة. التأكيد يعمل دون اتصال.
class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(barberRepoProvider).loadPayments();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(barberRepoProvider);
    final c = context.saloniColors;
    final all = repo.payments;
    final pending = all.where((p) => p.status == sa.PaymentStatus.awaitingConfirmation).toList();
    final done = all.where((p) => p.status == sa.PaymentStatus.confirmed).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(title: 'الدفعات', subtitle: 'اليوم'),
        Expanded(
          child: PageBody(onRefresh: repo.loadPayments, children: [
            Section(title: 'بانتظار التأكيد', children: [
              if (pending.isEmpty) const Muted('لا دفعات بانتظار التأكيد.'),
              for (var i = 0; i < pending.length; i++)
                i == 0
                    ? SurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Expanded(
                                  child: Text(pending[i].name,
                                      style: SaloniTextStyles.title3.copyWith(color: c.ink)),
                                ),
                                Text(repo.currency.format(pending[i].amountCents),
                                    style: SaloniTextStyles.title2.copyWith(color: c.ink, fontSize: 22)),
                              ],
                            ),
                            Text(
                              [
                                pending[i].services,
                                if (pending[i].at != null) 'انتهت ${timeAr(pending[i].at!)}',
                              ].where((s) => s.isNotEmpty).join(' · '),
                              style: SaloniTextStyles.caption.copyWith(color: c.inkMuted),
                            ),
                            const SizedBox(height: 12),
                            SaloniButton(
                              key: Key('pay-${pending[i].bookingId}'),
                              label: 'تأكيد استلام الدفع',
                              icon: SaloniIconName.coins,
                              size: SaloniButtonSize.lg,
                              block: true,
                              onPressed: () => repo.confirmPayment(
                                  pending[i].bookingId, pending[i].amountCents),
                            ),
                          ],
                        ),
                      )
                    : SurfaceCard(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(pending[i].name,
                                      style: SaloniTextStyles.bodyStrong.copyWith(color: c.ink, fontSize: 16)),
                                  Text(
                                    [
                                      pending[i].services,
                                      if (pending[i].at != null) timeAr(pending[i].at!),
                                    ].where((s) => s.isNotEmpty).join(' · '),
                                    style: SaloniTextStyles.caption.copyWith(color: c.inkMuted),
                                  ),
                                ],
                              ),
                            ),
                            Text(repo.currency.format(pending[i].amountCents),
                                style: SaloniTextStyles.title3.copyWith(color: c.ink)),
                            const SizedBox(width: 12),
                            SaloniButton(
                              key: Key('pay-${pending[i].bookingId}'),
                              label: 'تأكيد',
                              size: SaloniButtonSize.sm,
                              variant: SaloniButtonVariant.secondary,
                              onPressed: () => repo.confirmPayment(
                                  pending[i].bookingId, pending[i].amountCents),
                            ),
                          ],
                        ),
                      ),
            ]),
            Section(title: 'مؤكدة', children: [
              if (done.isEmpty) const Muted('لا دفعات مؤكدة بعد.'),
              for (final p in done)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: BorderDirectional(bottom: BorderSide(color: c.line)),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Text('${p.name} · ${p.services}',
                          style: SaloniTextStyles.body.copyWith(color: c.ink)),
                    ),
                    const StatusBadge(status: BookingStatus.payConfirmed, small: true),
                  ]),
                ),
            ]),
          ]),
        ),
      ],
    );
  }
}

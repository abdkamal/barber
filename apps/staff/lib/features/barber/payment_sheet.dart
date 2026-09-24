import 'package:flutter/material.dart';
import 'package:saloni_ui/saloni_ui.dart';

import '../../data/barber_repository.dart';
import '../common/ui.dart';

/// بعد الإنهاء: تأكيد استلام الدفع (مستقل عن حالة الخدمة — design.md §3).
///
/// [onConfirm] اختياري: افتراضيًا `repo.confirmPayment` (حجز طابور اليوم)؛
/// يُمرَّر `repo.confirmPreviousDayPayment` لحجز من يوم سابق أُغلق (ق24).
Future<void> showPaymentSheet(
  BuildContext context,
  BarberRepository repo,
  String bookingId,
  String name,
  int amountCents,
  String services, {
  Future<void> Function(int amountCents)? onConfirm,
}) {
  final confirm = onConfirm ?? (amount) => repo.confirmPayment(bookingId, amount);
  return showSaloniSheet<void>(context, (ctx) {
    final c = ctx.saloniColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const StatusBadge(status: BookingStatus.done),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(name, style: SaloniTextStyles.title3.copyWith(color: c.ink))),
            Text(repo.currency.format(amountCents),
                style: SaloniTextStyles.title2.copyWith(color: c.ink, fontSize: 22)),
          ],
        ),
        Text(services, style: SaloniTextStyles.caption.copyWith(color: c.inkMuted)),
        const SizedBox(height: 16),
        SaloniButton(
          key: const Key('confirm-payment'),
          label: 'تأكيد استلام الدفع',
          icon: SaloniIconName.coins,
          size: SaloniButtonSize.lg,
          block: true,
          onPressed: () async {
            await confirm(amountCents);
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
        ),
        const SizedBox(height: 10),
        SaloniButton(
          label: 'لاحقًا',
          variant: SaloniButtonVariant.ghost,
          block: true,
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ],
    );
  });
}

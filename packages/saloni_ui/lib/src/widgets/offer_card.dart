import 'package:flutter/material.dart';

import '../theme/saloni_theme.dart';
import '../tokens/saloni_radius.dart';
import '../tokens/saloni_spacing.dart';
import '../tokens/saloni_typography.dart';
import 'saloni_button.dart';

/// بطاقة عرض أقرب وقت متاح مع عدّاد تنازلي — `OfferCard` في `index.d.ts`.
class OfferCard extends StatelessWidget {
  const OfferCard({
    super.key,
    required this.requested,
    required this.offered,
    required this.barber,
    required this.secondsLeft,
    this.total = 120,
    this.onAccept,
    this.onDecline,
  });

  final String requested;
  final String offered;
  final String barber;
  final int secondsLeft;
  final int total;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    final pct = total <= 0 ? 0 : (100 * secondsLeft / total).clamp(0, 100).round();
    final mm = (secondsLeft ~/ 60).toString();
    final ss = (secondsLeft % 60).toString().padLeft(2, '0');

    return Semantics(
      label: 'أقرب وقت متاح',
      container: true,
      child: Container(
        padding: const EdgeInsets.all(SaloniSpacing.space5),
        decoration: BoxDecoration(color: c.steelSoft, borderRadius: SaloniRadius.xlAll),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                style: SaloniTextStyles.body.copyWith(color: c.ink),
                children: [
                  const TextSpan(text: 'الساعة '),
                  TextSpan(text: requested),
                  const TextSpan(text: ' غير متاحة. أقرب وقت متاح:'),
                ],
              ),
            ),
            // Wrap, not Row: a long barber name moves to the next line instead of overflowing.
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: SaloniSpacing.space1,
              children: [
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    offered,
                    style: TextStyle(
                      fontFamily: SaloniFonts.display,
                      fontSize: 36,
                      height: 44 / 36,
                      fontWeight: FontWeight.w500,
                      color: c.steel,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Text(
                  'عند $barber',
                  style: SaloniTextStyles.body.copyWith(color: c.inkMuted),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: SaloniSpacing.space1),
              child: ClipRRect(
                borderRadius: SaloniRadius.fullAll,
                child: SizedBox(
                  height: 8,
                  child: Stack(
                    children: [
                      Container(color: c.surfaceSunken),
                      FractionallySizedBox(
                        widthFactor: pct / 100,
                        child: Container(color: c.steel),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: SaloniSpacing.space1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'محجوز لك لمدة ',
                    style: SaloniTextStyles.caption.copyWith(color: c.inkMuted),
                  ),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      '$mm:$ss',
                      style: SaloniTextStyles.caption.copyWith(
                        color: c.inkMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: SaloniSpacing.space1),
              child: Row(
                children: [
                  Expanded(
                    child: SaloniButton(
                      label: 'احجز هذا الوقت',
                      block: true,
                      onPressed: onAccept,
                    ),
                  ),
                  const SizedBox(width: SaloniSpacing.space3),
                  Expanded(
                    child: SaloniButton(
                      label: 'لا، شكرًا',
                      variant: SaloniButtonVariant.secondary,
                      block: true,
                      onPressed: onDecline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

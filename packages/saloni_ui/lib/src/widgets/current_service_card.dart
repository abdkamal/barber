import 'package:flutter/material.dart';

import '../icons/saloni_icon_name.dart';
import '../theme/saloni_theme.dart';
import '../tokens/saloni_radius.dart';
import '../tokens/saloni_spacing.dart';
import '../tokens/saloni_typography.dart';
import 'saloni_button.dart';
import 'status_badge.dart';

/// بطاقة الخدمة الجارية — `CurrentServiceCard` في `index.d.ts`.
///
/// تُظهر حالة تجاوز المدة المقدرة (over-100%) بحدود وميتر ونص تحذيري بلون
/// `warning`، وزرًا كبيرًا لإنهاء الخدمة.
class CurrentServiceCard extends StatelessWidget {
  const CurrentServiceCard({
    super.key,
    required this.customer,
    required this.services,
    required this.startedAt,
    required this.elapsed,
    required this.estimate,
    this.onEnd,
    this.onEdit,
  });

  final String customer;
  final String services;
  final String startedAt;

  /// الدقائق المنقضية.
  final int elapsed;

  /// الدقائق المقدّرة.
  final int estimate;
  final VoidCallback? onEnd;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    final pct = estimate <= 0 ? 100 : (100 * elapsed / estimate).clamp(0, 100).round();
    final over = elapsed > estimate;

    return Semantics(
      label: 'الخدمة الجارية',
      container: true,
      child: Container(
        padding: const EdgeInsets.all(SaloniSpacing.space5),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          border: Border.all(color: over ? c.warning : c.line),
          borderRadius: SaloniRadius.xlAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const StatusBadge(status: BookingStatus.inService),
                const SizedBox(width: SaloniSpacing.space2),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      style: SaloniTextStyles.caption.copyWith(color: c.inkMuted),
                      children: [
                        const TextSpan(text: 'بدأت '),
                        TextSpan(text: startedAt),
                      ],
                    ),
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: SaloniSpacing.space2),
              child: Text(
                customer,
                style: SaloniTextStyles.title2.copyWith(color: c.ink),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      services,
                      style: SaloniTextStyles.body.copyWith(color: c.inkMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onEdit != null)
                    TextButton(
                      onPressed: onEdit,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(44, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'تعديل الخدمة',
                        style: SaloniTextStyles.label.copyWith(color: c.primary),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: SaloniSpacing.space2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontFamily: SaloniFonts.display,
                          fontSize: 40,
                          height: 44 / 40,
                          fontWeight: FontWeight.w500,
                          color: over ? c.warning : c.ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        children: [
                          TextSpan(text: '$elapsed'),
                          TextSpan(
                            text: ' د',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w400,
                              color: c.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: SaloniSpacing.space2),
                  Flexible(
                    child: Text(
                      'من $estimate د مقدّرة',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: c.inkMuted),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: SaloniSpacing.space2),
              child: ClipRRect(
                borderRadius: SaloniRadius.fullAll,
                child: SizedBox(
                  height: 8,
                  child: Stack(
                    children: [
                      Container(color: c.surfaceSunken),
                      FractionallySizedBox(
                        widthFactor: pct / 100,
                        child: Container(color: over ? c.warning : c.primary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (over)
              Padding(
                padding: const EdgeInsets.only(top: SaloniSpacing.space2),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: SaloniSpacing.space3,
                    vertical: SaloniSpacing.space2,
                  ),
                  decoration: BoxDecoration(
                    color: c.warningSoft,
                    borderRadius: SaloniRadius.smAll,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SaloniIcon(SaloniIconName.warning, size: 16, color: c.warning),
                      const SizedBox(width: SaloniSpacing.space2),
                      Flexible(
                        child: Text(
                          'تجاوزت الخدمة مدتها المقدرة — لا تنسَ الضغط على «إنهاء»',
                          style: SaloniTextStyles.caption.copyWith(color: c.warning),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: SaloniSpacing.space2),
              child: SaloniButton(
                label: 'إنهاء الخدمة',
                variant: SaloniButtonVariant.primary,
                size: SaloniButtonSize.lg,
                icon: SaloniIconName.checkCircle,
                block: true,
                onPressed: onEnd,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/saloni_theme.dart';
import '../tokens/saloni_radius.dart';
import '../tokens/saloni_spacing.dart';
import '../tokens/saloni_typography.dart';
import 'status_badge.dart' show SaloniTone;

/// بطاقة إحصائية مصغّرة بأعمدة صغيرة — `StatTile` في `index.d.ts`.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.delta,
    this.deltaTone,
    this.series,
  });

  final String label;
  final String value;
  final String? unit;
  final String? delta;
  final SaloniTone? deltaTone;
  final List<double>? series;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    final max = (series == null || series!.isEmpty)
        ? 1.0
        : series!.reduce((a, b) => a > b ? a : b).clamp(1, double.infinity);

    Color deltaColor;
    switch (deltaTone) {
      case SaloniTone.success:
        deltaColor = c.success;
        break;
      case SaloniTone.warning:
        deltaColor = c.warning;
        break;
      case SaloniTone.danger:
        deltaColor = c.danger;
        break;
      default:
        deltaColor = c.inkMuted;
    }

    return Semantics(
      label: '$label: $value ${unit ?? ''}',
      container: true,
      child: Container(
        padding: const EdgeInsets.all(SaloniSpacing.space4),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          border: Border.all(color: c.line),
          borderRadius: SaloniRadius.lgAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: SaloniTextStyles.caption.copyWith(color: c.inkMuted)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    value,
                    style: SaloniTextStyles.stat.copyWith(
                      color: c.ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (unit != null)
                  Text(
                    ' $unit',
                    style: SaloniTextStyles.bodyLg.copyWith(
                      color: c.inkMuted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
              ],
            ),
            if (delta != null)
              Text(delta!, style: SaloniTextStyles.caption.copyWith(color: deltaColor)),
            if (series != null && series!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: SaloniSpacing.space2),
                child: ExcludeSemantics(
                  child: SizedBox(
                    height: 40,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < series!.length; i++) ...[
                          if (i != 0) const SizedBox(width: 4),
                          Expanded(
                            child: FractionallySizedBox(
                              heightFactor: (series![i] / max).clamp(0.06, 1),
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: i == series!.length - 1
                                      ? c.chart1
                                      : c.primarySoft,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

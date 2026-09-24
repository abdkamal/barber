import 'package:flutter/material.dart';

import '../icons/saloni_icon_name.dart';
import '../theme/saloni_theme.dart';
import '../tokens/saloni_radius.dart';
import '../tokens/saloni_spacing.dart';
import '../tokens/saloni_typography.dart';
import '../tokens/saloni_colors.dart';

class SaloniHoursDay {
  const SaloniHoursDay({
    required this.day,
    this.from,
    this.to,
    this.closed = false,
    this.today = false,
  });
  final String day;
  final String? from;
  final String? to;
  final bool closed;
  final bool today;
}

/// قائمة ساعات العمل — `HoursList` في `index.d.ts`.
class HoursList extends StatelessWidget {
  const HoursList({super.key, this.openNow, required this.days});

  final bool? openNow;
  final List<SaloniHoursDay> days;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Semantics(
      label: 'ساعات العمل',
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
            Row(
              children: [
                SaloniIcon(SaloniIconName.clock, size: 20, color: c.ink),
                const SizedBox(width: SaloniSpacing.space2),
                Expanded(
                  child: Text(
                    'ساعات العمل',
                    overflow: TextOverflow.ellipsis,
                    style: SaloniTextStyles.body.copyWith(
                      color: c.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (openNow != null) ...[
                  const SizedBox(width: SaloniSpacing.space2),
                  _openBadge(c, openNow!),
                ],
              ],
            ),
            const SizedBox(height: SaloniSpacing.space2),
            for (final d in days)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        d.day,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 22 / 14,
                          color: d.today ? c.primary : c.inkMuted,
                          fontWeight: d.today ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(width: SaloniSpacing.space2),
                    if (d.closed)
                      Text(
                        'مغلق',
                        style: TextStyle(
                          fontSize: 14,
                          height: 22 / 14,
                          color: d.today ? c.primary : c.ink,
                          fontWeight: d.today ? FontWeight.w600 : FontWeight.w400,
                        ),
                      )
                    else
                      Flexible(
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            '${d.from} – ${d.to}',
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontSize: 14,
                              height: 22 / 14,
                              color: d.today ? c.primary : c.ink,
                              fontWeight: d.today ? FontWeight.w600 : FontWeight.w400,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
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

  Widget _openBadge(SaloniColors c, bool open) {
    final bg = open ? c.successSoft : c.surfaceSunken;
    final fg = open ? c.success : c.inkMuted;
    return Semantics(
      label: open ? 'مفتوح الآن' : 'مغلق الآن',
      child: Container(
        height: 24,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: SaloniRadius.fullAll),
        child: Text(
          open ? 'مفتوح الآن' : 'مغلق الآن',
          style: SaloniTextStyles.caption.copyWith(
            color: fg,
            height: 1,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

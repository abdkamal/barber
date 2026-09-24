import 'package:flutter/material.dart';

import '../theme/saloni_theme.dart';
import '../tokens/saloni_radius.dart';
import '../tokens/saloni_spacing.dart';
import '../tokens/saloni_typography.dart';
import 'status_badge.dart';

/// عنصر في قائمة الطابور — `QueueItem` في `index.d.ts`.
class QueueItem extends StatelessWidget {
  const QueueItem({
    super.key,
    required this.position,
    required this.name,
    required this.services,
    required this.eta,
    this.duration,
    this.status = BookingStatus.waiting,
    this.requested = false,
    this.requestedAt,
    this.walkIn = false,
    this.action,
  });

  final int position;
  final String name;
  final String services;
  final String eta;
  final String? duration;
  final BookingStatus status;
  final bool requested;
  final String? requestedAt;
  final bool walkIn;
  final Widget? action;

  bool get _called => status == BookingStatus.called;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Semantics(
      container: true,
      label: '$name، $services، $eta',
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: SaloniSpacing.space4,
          vertical: SaloniSpacing.space3,
        ),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          border: Border.all(color: _called ? c.warning : c.line),
          borderRadius: SaloniRadius.lgAll,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _called ? c.warningSoft : c.surfaceSunken,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$position',
                style: TextStyle(
                  fontFamily: SaloniFonts.displayFamily,
                  fontWeight: FontWeight.w600,
                  color: _called ? c.warning : c.inkMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: SaloniSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: SaloniSpacing.space2,
                    runSpacing: 4,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontFamily: SaloniFonts.displayFamily,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          height: 24 / 16,
                          color: c.ink,
                        ),
                      ),
                      if (requested)
                        StatusBadge(
                          status: BookingStatus.requested,
                          small: true,
                          label: 'ساعة ${requestedAt ?? ''}',
                        ),
                      if (walkIn)
                        const StatusBadge(status: BookingStatus.walkIn, small: true),
                      if (status != BookingStatus.waiting)
                        StatusBadge(status: status, small: true),
                    ],
                  ),
                  Text(
                    services,
                    style: SaloniTextStyles.caption.copyWith(color: c.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: SaloniSpacing.space3),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 88),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      eta,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: SaloniFonts.displayFamily,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        height: 26 / 18,
                        color: c.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  if (duration != null)
                    Text(
                      duration!,
                      overflow: TextOverflow.ellipsis,
                      style: SaloniTextStyles.caption.copyWith(
                        fontSize: 12,
                        height: 18 / 12,
                        color: c.inkMuted,
                      ),
                    ),
                ],
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: SaloniSpacing.space3),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

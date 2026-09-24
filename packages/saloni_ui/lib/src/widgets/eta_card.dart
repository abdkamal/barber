import 'package:flutter/material.dart';

import '../icons/saloni_icon_name.dart';
import '../theme/saloni_theme.dart';
import '../tokens/saloni_radius.dart';
import '../tokens/saloni_shadows.dart';
import '../tokens/saloni_spacing.dart';
import '../tokens/saloni_typography.dart';
import 'saloni_avatar.dart';
import 'status_badge.dart';

/// بطاقة الوقت المتوقع — `EtaCard` في `index.d.ts`.
///
/// عند `live == false` تُعرض الحالة الفاترة (`is-stale`): الوقت باهت، وشريط
/// سفلي بلون التنبيه يوضح أن الوقت تقديري (ق: لا تُخفِ التغيير).
class EtaCard extends StatelessWidget {
  const EtaCard({
    super.key,
    required this.eta,
    this.ampm = 'ص',
    this.status = BookingStatus.waiting,
    this.requested = false,
    required this.barber,
    required this.services,
    this.updated,
    this.originalEta,
    this.reason,
    this.live = true,
    this.staleFor,
  });

  final String eta;
  final String ampm;
  final BookingStatus status;

  /// `kind == 'requested'`.
  final bool requested;
  final String barber;
  final String services;
  final String? updated;
  final String? originalEta;
  final String? reason;
  final bool live;
  final String? staleFor;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final changed = originalEta != null && originalEta != eta;
    final stale = !live;

    return Semantics(
      label: 'موعدك المتوقع',
      container: true,
      child: Container(
        padding: const EdgeInsets.all(SaloniSpacing.space5),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.surfaceElevated, c.surfaceRaised],
          ),
          border: Border.all(color: c.line),
          borderRadius: SaloniRadius.xlAll,
          boxShadow: isDark ? SaloniShadows.shadow2Dark : SaloniShadows.shadow2Light,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: SaloniSpacing.space2,
              runSpacing: SaloniSpacing.space2,
              children: [
                StatusBadge(status: status),
                if (requested)
                  const StatusBadge(status: BookingStatus.requested, small: true),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: SaloniSpacing.space2),
              child: Text(
                status == BookingStatus.inService
                    ? 'بدأت خدمتك'
                    : 'يُتوقع أن تبدأ خدمتك',
                style: SaloniTextStyles.label.copyWith(
                  color: c.inkMuted,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        eta,
                        style: SaloniTextStyles.timeHero.copyWith(
                          color: stale ? c.inkMuted : c.ink,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: SaloniSpacing.space2),
                Text(
                  ampm,
                  style: SaloniTextStyles.bodyLg.copyWith(color: c.inkMuted),
                ),
              ],
            ),
            if (changed)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text.rich(
                  TextSpan(
                    style: SaloniTextStyles.caption.copyWith(color: c.inkMuted),
                    children: [
                      const TextSpan(text: 'كان متوقعًا '),
                      TextSpan(text: originalEta),
                      if (reason != null) TextSpan(text: ' — $reason'),
                    ],
                  ),
                ),
              ),
            Container(
              margin: const EdgeInsets.only(top: SaloniSpacing.space2),
              padding: const EdgeInsets.only(top: SaloniSpacing.space3),
              decoration: BoxDecoration(
                border: BorderDirectional(top: BorderSide(color: c.line)),
              ),
              child: Row(
                children: [
                  SaloniAvatar(name: barber, size: 36),
                  const SizedBox(width: SaloniSpacing.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          barber,
                          style: SaloniTextStyles.body.copyWith(
                            color: c.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          services,
                          style: SaloniTextStyles.caption.copyWith(
                            color: c.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: SaloniSpacing.space2),
              child: stale
                  ? Container(
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
                          SaloniIcon(
                            SaloniIconName.wifiSlash,
                            size: 16,
                            color: c.warning,
                          ),
                          const SizedBox(width: SaloniSpacing.space1),
                          Flexible(
                            child: Text(
                              'الوقت تقديري — لم يصلنا تحديث من الصالون منذ ${staleFor ?? 'دقائق'}',
                              style: SaloniTextStyles.caption.copyWith(
                                color: c.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Row(
                      children: [
                        SaloniIcon(
                          SaloniIconName.clockCounterClockwise,
                          size: 16,
                          color: c.inkMuted,
                        ),
                        const SizedBox(width: SaloniSpacing.space1),
                        Flexible(
                          child: Text(
                            'آخر تحديث ${updated ?? 'الآن'}',
                            overflow: TextOverflow.ellipsis,
                            style: SaloniTextStyles.caption.copyWith(
                              color: c.inkMuted,
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
}

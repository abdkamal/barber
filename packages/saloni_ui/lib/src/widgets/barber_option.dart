import 'package:flutter/material.dart';

import '../icons/saloni_icon_name.dart';
import '../theme/saloni_theme.dart';
import '../tokens/saloni_radius.dart';
import '../tokens/saloni_spacing.dart';
import '../tokens/saloni_typography.dart';
import 'saloni_avatar.dart';

/// خيار اختيار حلاق — `BarberOption` في `index.d.ts`.
class BarberOption extends StatelessWidget {
  const BarberOption({
    super.key,
    this.name,
    this.fastest = false,
    this.nextAt,
    this.wait,
    this.note,
    this.selected = false,
    this.unavailable = false,
    this.reason,
    this.onTap,
  });

  final String? name;
  final bool fastest;
  final String? nextAt;
  final String? wait;
  final String? note;
  final bool selected;
  final bool unavailable;
  final String? reason;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    final title = fastest ? 'الأسرع' : (name ?? '');
    final meta = unavailable
        ? (reason ?? 'غير متاح اليوم')
        : (fastest ? 'يختار النظام من يبدأ خدمتك أولًا' : (note ?? 'أقرب وقت لبدء خدمتك'));

    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      enabled: !unavailable,
      button: true,
      label: '$title، $meta',
      child: Material(
        color: unavailable ? c.surfaceSunken : c.surfaceRaised,
        borderRadius: SaloniRadius.lgAll,
        child: InkWell(
          borderRadius: SaloniRadius.lgAll,
          onTap: unavailable ? null : onTap,
          child: Container(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: SaloniSpacing.space4,
              vertical: SaloniSpacing.space3,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: selected ? c.primary : c.line),
              borderRadius: SaloniRadius.lgAll,
              boxShadow: selected
                  ? [BoxShadow(color: c.primary, spreadRadius: 1)]
                  : null,
            ),
            child: Row(
              children: [
                if (fastest)
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.primary,
                      shape: BoxShape.circle,
                    ),
                    child: SaloniIcon(
                      SaloniIconName.usersThree,
                      size: 22,
                      color: c.onPrimary,
                    ),
                  )
                else
                  SaloniAvatar(name: name ?? '', size: 44),
                const SizedBox(width: SaloniSpacing.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: SaloniFonts.displayFamily,
                          fontWeight: FontWeight.w600,
                          fontSize: 17,
                          height: 26 / 17,
                          color: c.ink,
                        ),
                      ),
                      Text(
                        meta,
                        style: SaloniTextStyles.caption.copyWith(
                          color: c.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!unavailable && nextAt != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          nextAt!,
                          style: TextStyle(
                            fontFamily: SaloniFonts.displayFamily,
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            height: 28 / 20,
                            color: c.ink,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                      if (wait != null)
                        Text(
                          wait!,
                          style: SaloniTextStyles.caption.copyWith(
                            fontSize: 12,
                            height: 18 / 12,
                            color: c.inkMuted,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

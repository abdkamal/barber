import 'package:flutter/material.dart';

import '../icons/saloni_icon_name.dart';
import '../theme/saloni_theme.dart';
import '../tokens/saloni_radius.dart';
import '../tokens/saloni_spacing.dart';
import '../tokens/saloni_typography.dart';

enum SaloniBannerTone { info, success, warning, danger }

/// شريط إشعار — `Banner` في `index.d.ts`.
class SaloniBanner extends StatelessWidget {
  const SaloniBanner({
    super.key,
    this.tone = SaloniBannerTone.info,
    this.title,
    this.body,
    this.action,
  });

  final SaloniBannerTone tone;
  final String? title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    final Color bg;
    final Color fg;
    final SaloniIconName icon;
    switch (tone) {
      case SaloniBannerTone.info:
        bg = c.steelSoft;
        fg = c.steel;
        icon = SaloniIconName.info;
        break;
      case SaloniBannerTone.success:
        bg = c.successSoft;
        fg = c.success;
        icon = SaloniIconName.checkCircle;
        break;
      case SaloniBannerTone.warning:
        bg = c.warningSoft;
        fg = c.warning;
        icon = SaloniIconName.warning;
        break;
      case SaloniBannerTone.danger:
        bg = c.dangerSoft;
        fg = c.danger;
        icon = SaloniIconName.xCircle;
        break;
    }

    return Semantics(
      liveRegion: tone == SaloniBannerTone.danger,
      container: true,
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: SaloniSpacing.space4,
          vertical: SaloniSpacing.space3,
        ),
        decoration: BoxDecoration(color: bg, borderRadius: SaloniRadius.mdAll),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SaloniIcon(icon, size: 22, color: fg),
            const SizedBox(width: SaloniSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null)
                    Text(
                      title!,
                      style: SaloniTextStyles.body.copyWith(
                        color: c.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (body != null)
                    Text(
                      body!,
                      style: SaloniTextStyles.label.copyWith(
                        color: c.ink,
                        fontWeight: FontWeight.w400,
                        height: 22 / 14,
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

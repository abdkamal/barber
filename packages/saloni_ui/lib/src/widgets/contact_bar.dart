import 'package:flutter/material.dart';

import '../icons/saloni_icon_name.dart';
import '../theme/saloni_theme.dart';
import '../tokens/saloni_radius.dart';
import '../tokens/saloni_spacing.dart';
import '../tokens/saloni_typography.dart';

class _ContactAction {
  const _ContactAction(this.icon, this.label, this.onTap);
  final SaloniIconName icon;
  final String label;
  final VoidCallback? onTap;
}

/// شريط التواصل — `ContactBar` في `index.d.ts`.
class ContactBar extends StatelessWidget {
  const ContactBar({
    super.key,
    this.address,
    this.phone,
    this.whatsapp,
    this.showMaps = false,
    this.instagram,
    this.onCall,
    this.onWhatsapp,
    this.onMaps,
    this.onInstagram,
  });

  final String? address;
  final String? phone;
  final String? whatsapp;
  final bool showMaps;
  final String? instagram;
  final VoidCallback? onCall;
  final VoidCallback? onWhatsapp;
  final VoidCallback? onMaps;
  final VoidCallback? onInstagram;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    final actions = <_ContactAction>[
      if (phone != null) _ContactAction(SaloniIconName.phone, 'اتصال', onCall),
      if (whatsapp != null)
        _ContactAction(SaloniIconName.whatsappLogo, 'واتساب', onWhatsapp),
      if (showMaps) _ContactAction(SaloniIconName.navigationArrow, 'الاتجاهات', onMaps),
      if (instagram != null)
        _ContactAction(SaloniIconName.instagramLogo, 'إنستغرام', onInstagram),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (address != null)
          Padding(
            padding: const EdgeInsets.only(bottom: SaloniSpacing.space3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SaloniIcon(SaloniIconName.mapPin, size: 18, color: c.inkMuted),
                const SizedBox(width: SaloniSpacing.space2),
                Expanded(
                  child: Text(
                    address!,
                    style: SaloniTextStyles.label.copyWith(
                      color: c.inkMuted,
                      fontWeight: FontWeight.w400,
                      height: 22 / 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Wrap(
          spacing: SaloniSpacing.space2,
          runSpacing: SaloniSpacing.space2,
          children: [
            for (final a in actions)
              SizedBox(
                width: 76,
                child: Semantics(
                  button: true,
                  label: a.label,
                  child: Material(
                    color: c.primarySoft,
                    borderRadius: SaloniRadius.mdAll,
                    child: InkWell(
                      onTap: a.onTap,
                      borderRadius: SaloniRadius.mdAll,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: SaloniSpacing.space2,
                          vertical: SaloniSpacing.space3,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SaloniIcon(a.icon, size: 22, color: c.primary),
                            const SizedBox(height: 4),
                            Text(
                              a.label,
                              style: SaloniTextStyles.caption.copyWith(
                                color: c.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

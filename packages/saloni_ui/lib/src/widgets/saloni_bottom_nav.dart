import 'package:flutter/material.dart';

import '../icons/saloni_icon_name.dart';
import '../theme/saloni_theme.dart';
import '../tokens/saloni_radius.dart';
import '../tokens/saloni_sizes.dart';
import '../tokens/saloni_typography.dart';

class SaloniNavItem {
  const SaloniNavItem({required this.icon, required this.label, this.badge});
  final SaloniIconName icon;
  final String label;
  final int? badge;
}

/// الشريط السفلي — `BottomNav` في `index.d.ts`.
class SaloniBottomNav extends StatelessWidget {
  const SaloniBottomNav({
    super.key,
    required this.items,
    this.active = 0,
    this.onTap,
  });

  final List<SaloniNavItem> items;
  final int active;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Semantics(
      container: true,
      label: 'التنقل الرئيسي',
      child: Container(
        height: SaloniSizes.navHeight,
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          border: BorderDirectional(top: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: _NavButton(
                  item: items[i],
                  selected: i == active,
                  onTap: onTap == null ? null : () => onTap!(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, this.onTap});
  final SaloniNavItem item;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    final color = selected ? c.primary : c.inkMuted;
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 56,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? c.primarySoft : Colors.transparent,
                      borderRadius: SaloniRadius.fullAll,
                    ),
                    child: SaloniIcon(item.icon, size: 24, color: color),
                  ),
                  if (item.badge != null && item.badge! > 0)
                    PositionedDirectional(
                      top: -2,
                      end: 6,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.warning,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          '${item.badge}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: c.surfaceRaised,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                item.label,
                style: SaloniTextStyles.caption.copyWith(
                  fontSize: 12,
                  height: 16 / 12,
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

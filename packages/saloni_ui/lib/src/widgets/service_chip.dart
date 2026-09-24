import 'package:flutter/material.dart';

import '../icons/saloni_icon_name.dart';
import '../theme/saloni_theme.dart';
import '../tokens/saloni_radius.dart';
import '../tokens/saloni_spacing.dart';
import '../tokens/saloni_typography.dart';

/// شريحة خدمة قابلة للاختيار — `ServiceChip` في `index.d.ts`.
class ServiceChip extends StatefulWidget {
  const ServiceChip({
    super.key,
    required this.name,
    required this.minutes,
    required this.price,
    this.currency = 'ر.س',
    this.selected = false,
    this.onToggle,
  });

  final String name;
  final int minutes;
  final String price;
  final String currency;
  final bool selected;
  final ValueChanged<bool>? onToggle;

  @override
  State<ServiceChip> createState() => _ServiceChipState();
}

class _ServiceChipState extends State<ServiceChip> {
  late bool _on = widget.selected;

  @override
  void didUpdateWidget(covariant ServiceChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) _on = widget.selected;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Semantics(
      button: true,
      checked: _on,
      label: '${widget.name}، ${widget.minutes} دقيقة، ${widget.price} ${widget.currency}',
      child: Material(
        color: _on ? c.primarySoft : c.surfaceRaised,
        borderRadius: SaloniRadius.lgAll,
        child: InkWell(
          borderRadius: SaloniRadius.lgAll,
          onTap: () {
            setState(() => _on = !_on);
            widget.onToggle?.call(_on);
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: SaloniSpacing.space4,
              vertical: SaloniSpacing.space3,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: _on ? c.primary : c.line),
              borderRadius: SaloniRadius.lgAll,
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _on ? c.primary : c.surfaceRaised,
                    border: Border.all(
                      color: _on ? c.primary : c.lineStrong,
                      width: 1.5,
                    ),
                    borderRadius: SaloniRadius.smAll,
                  ),
                  child: _on
                      ? SaloniIcon(
                          SaloniIconName.check,
                          size: 16,
                          color: c.onPrimary,
                        )
                      : null,
                ),
                const SizedBox(width: SaloniSpacing.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.name,
                        style: SaloniTextStyles.body.copyWith(
                          color: c.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SaloniIcon(
                            SaloniIconName.clock,
                            size: 16,
                            color: c.inkMuted,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${widget.minutes} دقيقة',
                              overflow: TextOverflow.ellipsis,
                              style: SaloniTextStyles.caption.copyWith(
                                color: c.inkMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: SaloniSpacing.space3),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    '${widget.price} ',
                    style: TextStyle(
                      fontFamily: SaloniFonts.display,
                      fontWeight: FontWeight.w500,
                      color: c.ink,
                    ),
                  ),
                ),
                Text(
                  widget.currency,
                  style: TextStyle(
                    fontFamily: SaloniFonts.display,
                    fontWeight: FontWeight.w500,
                    color: c.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

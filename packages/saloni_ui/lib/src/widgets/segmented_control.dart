import 'package:flutter/material.dart';

import '../icons/saloni_icon_name.dart';
import '../theme/saloni_theme.dart';
import '../tokens/saloni_radius.dart';
import '../tokens/saloni_shadows.dart';
import '../tokens/saloni_typography.dart';

class SaloniSegmentedOption {
  const SaloniSegmentedOption({
    required this.value,
    required this.label,
    this.icon,
  });
  final String value;
  final String label;
  final SaloniIconName? icon;
}

/// مجموعة مقسّمة — `SegmentedControl` في `index.d.ts`.
class SaloniSegmentedControl extends StatefulWidget {
  const SaloniSegmentedControl({
    super.key,
    required this.label,
    required this.options,
    this.value,
    this.onChanged,
  });

  final String label;
  final List<SaloniSegmentedOption> options;
  final String? value;
  final ValueChanged<String>? onChanged;

  @override
  State<SaloniSegmentedControl> createState() =>
      _SaloniSegmentedControlState();
}

class _SaloniSegmentedControlState extends State<SaloniSegmentedControl> {
  late String _value = widget.value ?? widget.options.first.value;

  @override
  void didUpdateWidget(covariant SaloniSegmentedControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != null && widget.value != oldWidget.value) {
      _value = widget.value!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Semantics(
      label: widget.label,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: c.surfaceSunken,
          borderRadius: SaloniRadius.mdAll,
        ),
        child: Row(
          children: [
            for (final o in widget.options)
              Expanded(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    end: o == widget.options.last ? 0 : 4,
                  ),
                  child: _Segment(
                    option: o,
                    selected: o.value == _value,
                    onTap: () {
                      setState(() => _value = o.value);
                      widget.onChanged?.call(o.value);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.option,
    required this.selected,
    required this.onTap,
  });
  final SaloniSegmentedOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      label: option.label,
      child: Material(
        color: selected ? c.surfaceRaised : Colors.transparent,
        borderRadius: BorderRadius.circular(SaloniRadius.md - 4),
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SaloniRadius.md - 4),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            decoration: selected
                ? BoxDecoration(
                    color: c.surfaceRaised,
                    borderRadius: BorderRadius.circular(SaloniRadius.md - 4),
                    boxShadow: Theme.of(context).brightness == Brightness.dark
                        ? SaloniShadows.shadow1Dark
                        : SaloniShadows.shadow1Light,
                  )
                : null,
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (option.icon != null) ...[
                  SaloniIcon(
                    option.icon!,
                    size: 18,
                    color: selected ? c.ink : c.inkMuted,
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  option.label,
                  style: TextStyle(
                    fontFamily: SaloniFonts.text,
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? c.ink : c.inkMuted,
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

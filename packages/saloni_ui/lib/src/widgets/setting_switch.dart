import 'package:flutter/material.dart';

import '../theme/saloni_theme.dart';
import '../tokens/saloni_radius.dart';
import '../tokens/saloni_spacing.dart';
import '../tokens/saloni_typography.dart';
import 'help_hint.dart';

/// صف إعداد بمفتاح تبديل — `Switch` في `index.d.ts` (سُمّي `SettingSwitch`
/// في Dart لتفادي التعارض مع `Switch` من Material).
class SettingSwitch extends StatefulWidget {
  const SettingSwitch({
    super.key,
    required this.label,
    this.description,
    this.checked = false,
    this.onChanged,
    this.help,
  });

  final String label;
  final String? description;
  final bool checked;
  final ValueChanged<bool>? onChanged;

  /// شرح الإعداد: ⓘ بجانب العنوان يفتح ورقة الشرح.
  final SaloniHelp? help;

  @override
  State<SettingSwitch> createState() => _SettingSwitchState();
}

class _SettingSwitchState extends State<SettingSwitch> {
  late bool _on = widget.checked;

  @override
  void didUpdateWidget(covariant SettingSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.checked != oldWidget.checked) _on = widget.checked;
  }

  void _toggle() {
    setState(() => _on = !_on);
    widget.onChanged?.call(_on);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Container(
      color: c.surfaceRaised,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: SaloniSpacing.space4,
        vertical: SaloniSpacing.space3,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SaloniLabelWithHelp(
                  label: widget.label,
                  help: widget.help,
                  style: SaloniTextStyles.label.copyWith(
                    color: c.ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (widget.description != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      widget.description!,
                      style: SaloniTextStyles.caption.copyWith(color: c.inkMuted),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: SaloniSpacing.space4),
          Semantics(
            toggled: _on,
            label: widget.label,
            child: GestureDetector(
              onTap: _toggle,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 52,
                height: 48,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 52,
                    height: 32,
                    padding: const EdgeInsets.all(3),
                    alignment: _on
                        ? AlignmentDirectional.centerEnd
                        : AlignmentDirectional.centerStart,
                    decoration: BoxDecoration(
                      color: _on ? c.primary : c.surfaceSunken,
                      borderRadius: SaloniRadius.fullAll,
                      border: Border.all(
                        color: _on ? c.primary : c.lineStrong,
                        width: 1.5,
                      ),
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 23,
                      height: 23,
                      decoration: BoxDecoration(
                        color: _on ? c.onPrimary : c.lineStrong,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

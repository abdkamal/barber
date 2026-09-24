import 'package:flutter/material.dart';

import '../icons/saloni_icon_name.dart';
import '../theme/saloni_theme.dart';
import '../tokens/saloni_radius.dart';
import '../tokens/saloni_sizes.dart';
import '../tokens/saloni_spacing.dart';
import '../tokens/saloni_typography.dart';

enum SaloniButtonVariant { primary, secondary, ghost, danger }

enum SaloniButtonSize { sm, md, lg }

/// زر «صالوني» — `Button` في `index.d.ts`.
class SaloniButton extends StatelessWidget {
  const SaloniButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = SaloniButtonVariant.primary,
    this.size = SaloniButtonSize.md,
    this.icon,
    this.block = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final SaloniButtonVariant variant;
  final SaloniButtonSize size;
  final SaloniIconName? icon;
  final bool block;
  final bool loading;

  bool get _disabled => onPressed == null || loading;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;

    final double minHeight = switch (size) {
      SaloniButtonSize.sm => SaloniSizes.controlSm,
      SaloniButtonSize.md => SaloniSizes.controlMd,
      SaloniButtonSize.lg => SaloniSizes.controlLg,
    };
    final EdgeInsetsGeometry padding = switch (size) {
      SaloniButtonSize.sm => const EdgeInsetsDirectional.symmetric(
        horizontal: SaloniSpacing.space4,
      ),
      SaloniButtonSize.md => const EdgeInsetsDirectional.symmetric(
        horizontal: SaloniSpacing.space5,
      ),
      SaloniButtonSize.lg => const EdgeInsetsDirectional.symmetric(
        horizontal: SaloniSpacing.space6,
      ),
    };
    final BorderRadius radius = switch (size) {
      SaloniButtonSize.sm => SaloniRadius.smAll,
      SaloniButtonSize.md => SaloniRadius.mdAll,
      SaloniButtonSize.lg => SaloniRadius.lgAll,
    };
    final TextStyle textStyle = switch (size) {
      SaloniButtonSize.sm => SaloniTextStyles.label,
      SaloniButtonSize.md => SaloniTextStyles.body,
      SaloniButtonSize.lg => SaloniTextStyles.bodyLg,
    }.copyWith(fontWeight: FontWeight.w600, height: 1);
    final double iconSize = size == SaloniButtonSize.lg ? 24 : 20;

    Color bg;
    Color fg;
    Color? borderColor;
    switch (variant) {
      case SaloniButtonVariant.primary:
        bg = c.primary;
        fg = c.onPrimary;
        break;
      case SaloniButtonVariant.secondary:
        bg = c.surfaceRaised;
        fg = c.ink;
        borderColor = c.lineStrong;
        break;
      case SaloniButtonVariant.ghost:
        bg = Colors.transparent;
        fg = c.primary;
        break;
      case SaloniButtonVariant.danger:
        bg = c.danger;
        fg = c.onDanger;
        break;
    }

    Widget content = Row(
      mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (icon != null)
          SaloniIcon(icon!, size: iconSize, color: fg),
        if (loading || icon != null) const SizedBox(width: SaloniSpacing.space2),
        Flexible(
          child: Text(
            label,
            style: textStyle.copyWith(color: fg),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    final button = Opacity(
      opacity: _disabled && !loading ? 0.45 : (loading ? 0.8 : 1),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: borderColor != null
              ? BorderSide(color: borderColor)
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: _disabled ? null : onPressed,
          borderRadius: radius,
          focusColor: c.focus.withValues(alpha: 0.2),
          child: Container(
            constraints: BoxConstraints(minHeight: minHeight, minWidth: minHeight),
            padding: padding,
            alignment: Alignment.center,
            child: content,
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: !_disabled,
      label: label,
      child: block ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

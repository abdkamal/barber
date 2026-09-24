import 'package:flutter/material.dart';

import '../icons/saloni_icon_name.dart';
import '../theme/saloni_theme.dart';
import '../tokens/saloni_radius.dart';
import '../tokens/saloni_sizes.dart';
import '../tokens/saloni_spacing.dart';
import '../tokens/saloni_typography.dart';
import 'help_hint.dart';

enum SaloniTextFieldType { text, password, tel, number }

/// حقل إدخال «صالوني» — `TextField` في `index.d.ts`.
class SaloniTextField extends StatefulWidget {
  const SaloniTextField({
    super.key,
    required this.label,
    this.controller,
    this.type = SaloniTextFieldType.text,
    this.placeholder,
    this.prefix,
    this.hint,
    this.error,
    this.textDirection,
    this.onChanged,
    this.help,
  });

  final String label;
  final TextEditingController? controller;
  final SaloniTextFieldType type;
  final String? placeholder;

  /// بادئة تُعرض من اليسار لليمين دومًا (أرقام هواتف/رموز).
  final String? prefix;
  final String? hint;
  final String? error;
  final TextDirection? textDirection;
  final ValueChanged<String>? onChanged;

  /// شرح الحقل: ⓘ بجانب العنوان يفتح ورقة الشرح، و`help.summary` يُعرض سطرًا
  /// مساعدًا تحت الحقل إن لم يُعطَ [hint].
  final SaloniHelp? help;

  @override
  State<SaloniTextField> createState() => _SaloniTextFieldState();
}

class _SaloniTextFieldState extends State<SaloniTextField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    final hasError = widget.error != null && widget.error!.isNotEmpty;
    final borderColor = hasError ? c.danger : c.lineStrong;
    final isPassword = widget.type == SaloniTextFieldType.password;
    final hint = (widget.hint?.isNotEmpty ?? false) ? widget.hint : widget.help?.summary;

    TextInputType keyboardType;
    switch (widget.type) {
      case SaloniTextFieldType.tel:
        keyboardType = TextInputType.phone;
        break;
      case SaloniTextFieldType.number:
        keyboardType = TextInputType.number;
        break;
      default:
        keyboardType = TextInputType.text;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SaloniLabelWithHelp(label: widget.label, help: widget.help),
        SizedBox(height: widget.help == null ? SaloniSpacing.space2 : SaloniSpacing.space1),
        Container(
          constraints: const BoxConstraints(minHeight: SaloniSizes.controlMd),
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            border: Border.all(color: borderColor),
            borderRadius: SaloniRadius.mdAll,
          ),
          child: Row(
            children: [
              if (widget.prefix != null)
                Container(
                  padding: const EdgeInsetsDirectional.only(
                    start: SaloniSpacing.space4,
                    end: SaloniSpacing.space3,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: BorderDirectional(
                      end: BorderSide(color: c.line),
                    ),
                  ),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      widget.prefix!,
                      style: SaloniTextStyles.body.copyWith(
                        color: c.inkMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: SaloniSpacing.space4,
                  ),
                  child: TextField(
                    controller: widget.controller,
                    obscureText: isPassword && _obscure,
                    keyboardType: keyboardType,
                    textDirection: widget.textDirection,
                    onChanged: widget.onChanged,
                    style: SaloniTextStyles.bodyLg.copyWith(color: c.ink),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText: widget.placeholder,
                      hintStyle: SaloniTextStyles.bodyLg.copyWith(
                        color: c.inkSubtle,
                      ),
                    ),
                  ),
                ),
              ),
              if (isPassword)
                Semantics(
                  button: true,
                  label: _obscure ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور',
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: SaloniIcon(
                        _obscure
                            ? SaloniIconName.eye
                            : SaloniIconName.eyeSlash,
                        color: c.inkMuted,
                        size: 20,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (hasError || (hint?.isNotEmpty ?? false)) ...[
          const SizedBox(height: SaloniSpacing.space2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasError)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: SaloniIcon(
                    SaloniIconName.warning,
                    size: 16,
                    color: c.danger,
                  ),
                ),
              Flexible(
                child: Text(
                  hasError ? widget.error! : hint!,
                  style: SaloniTextStyles.caption.copyWith(
                    color: hasError ? c.danger : c.inkMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

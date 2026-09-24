import 'package:flutter/material.dart';

import '../icons/saloni_icon_name.dart';
import '../theme/saloni_theme.dart';
import '../tokens/saloni_radius.dart';
import '../tokens/saloni_spacing.dart';
import '../tokens/saloni_typography.dart';
import 'saloni_button.dart';

/// شرح خيار غير واضح: عنوان قصير + شرح بلغة بسيطة + مثال عملي.
///
/// النص الكامل يظهر في ورقة سفلية عند الضغط على ⓘ ([SaloniHelpHint])، ويمكن
/// عرض [summary] (سطر واحد) تحت الحقل مباشرة حيث تسمح المساحة.
@immutable
class SaloniHelp {
  const SaloniHelp({
    required this.title,
    required this.body,
    this.example,
    this.summary,
  });

  /// عنوان الورقة — غالبًا اسم الإعداد نفسه.
  final String title;

  /// الشرح: ماذا يفعل هذا الخيار، بجمل قصيرة بلا مصطلحات تقنية.
  final String body;

  /// مثال عملي من يوم الصالون («مثال: ...» يُضاف تلقائيًا).
  final String? example;

  /// سطر مساعد قصير يُعرض تحت الحقل (اختياري).
  final String? summary;
}

/// يفتح ورقة الشرح لـ [help].
Future<void> showSaloniHelpSheet(BuildContext context, SaloniHelp help) {
  final c = context.saloniColors;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: c.surfaceRaised,
    barrierColor: c.overlay,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(SaloniRadius.xl)),
    ),
    builder: (ctx) => SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        SaloniSpacing.space4,
        SaloniSpacing.space6,
        SaloniSpacing.space4,
        SaloniSpacing.space6,
      ),
      child: _HelpSheetBody(help: help),
    ),
  );
}

class _HelpSheetBody extends StatelessWidget {
  const _HelpSheetBody({required this.help});
  final SaloniHelp help;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Column(
      key: const Key('saloni-help-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            SaloniIcon(SaloniIconName.info, color: c.primary, size: 22),
            const SizedBox(width: SaloniSpacing.space2),
            Expanded(
              child: Text(help.title, style: SaloniTextStyles.title3.copyWith(color: c.ink)),
            ),
          ],
        ),
        const SizedBox(height: SaloniSpacing.space3),
        Text(help.body, style: SaloniTextStyles.body.copyWith(color: c.ink)),
        if (help.example != null) ...[
          const SizedBox(height: SaloniSpacing.space3),
          Container(
            padding: const EdgeInsets.all(SaloniSpacing.space3),
            decoration: BoxDecoration(
              color: c.surfaceSunken,
              borderRadius: SaloniRadius.mdAll,
              border: Border.all(color: c.line),
            ),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: 'مثال: ',
                  style: SaloniTextStyles.bodyStrong.copyWith(color: c.primary),
                ),
                TextSpan(text: help.example),
              ]),
              style: SaloniTextStyles.body.copyWith(color: c.inkMuted),
            ),
          ),
        ],
        const SizedBox(height: SaloniSpacing.space5),
        SaloniButton(
          label: 'فهمت',
          block: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// أيقونة ⓘ صغيرة بجانب عنوان الخيار تفتح ورقة الشرح. مساحة اللمس 40×40
/// (أو 32×32 بجانب عنوان حقل مع [compact])، ولها وصف لقارئ الشاشة
/// «شرح: {العنوان}».
class SaloniHelpHint extends StatelessWidget {
  const SaloniHelpHint(this.help, {super.key, this.size = 18, this.compact = false});

  final SaloniHelp help;
  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Semantics(
      button: true,
      label: 'شرح: ${help.title}',
      excludeSemantics: true,
      child: InkResponse(
        onTap: () => showSaloniHelpSheet(context, help),
        radius: compact ? 16 : 20,
        child: SizedBox(
          width: compact ? 32 : 40,
          height: compact ? 32 : 40,
          child: Center(child: SaloniIcon(SaloniIconName.info, size: size, color: c.primary)),
        ),
      ),
    );
  }
}

/// عنوان خيار + ⓘ اختياري بجانبه — لبناء عناوين الحقول والصفوف بشكل موحّد.
class SaloniLabelWithHelp extends StatelessWidget {
  const SaloniLabelWithHelp({super.key, required this.label, this.help, this.style});

  final String label;
  final SaloniHelp? help;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    final text = Text(label, style: style ?? SaloniTextStyles.label.copyWith(color: c.ink));
    if (help == null) return text;
    return Row(
      children: [
        Flexible(child: text),
        const SizedBox(width: 2),
        SaloniHelpHint(help!, compact: true),
      ],
    );
  }
}

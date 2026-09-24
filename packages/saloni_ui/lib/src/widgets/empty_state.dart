import 'package:flutter/material.dart';

import '../icons/saloni_icon_name.dart';
import '../theme/saloni_theme.dart';
import '../tokens/saloni_spacing.dart';
import '../tokens/saloni_typography.dart';

/// حالة فارغة — `EmptyState` في `index.d.ts`.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon = SaloniIconName.coffee,
    required this.title,
    this.body,
    this.action,
  });

  final SaloniIconName icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SaloniSpacing.space6,
          vertical: SaloniSpacing.space12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              margin: const EdgeInsets.only(bottom: SaloniSpacing.space2),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.primarySoft, shape: BoxShape.circle),
              child: SaloniIcon(icon, size: 32, color: c.primary),
            ),
            Text(
              title,
              textAlign: TextAlign.center,
              style: SaloniTextStyles.title3.copyWith(color: c.ink),
            ),
            if (body != null)
              Padding(
                padding: const EdgeInsets.only(top: SaloniSpacing.space2),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    body!,
                    textAlign: TextAlign.center,
                    style: SaloniTextStyles.body.copyWith(color: c.inkMuted),
                  ),
                ),
              ),
            if (action != null)
              Padding(
                padding: const EdgeInsets.only(top: SaloniSpacing.space3),
                child: action!,
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/saloni_theme.dart';
import '../tokens/saloni_radius.dart';
import '../tokens/saloni_spacing.dart';
import '../tokens/saloni_typography.dart';

/// شريط تقدّم الطابور بلا أرقام — `QueueProgress` في `index.d.ts` (ق39).
class QueueProgress extends StatelessWidget {
  const QueueProgress({
    super.key,
    required this.done,
    required this.ahead,
    this.label,
    this.updated,
    this.note,
  });

  /// عدد النقاط المنجزة (الأدوار التي مرّت).
  final int done;

  /// عدد النقاط المتبقية قبل الدور الحالي.
  final int ahead;

  final String? label;
  final String? updated;
  final String? note;

  /// أقصى عدد نقاط «منجزة» تُعرض فرديًا قبل ضغطها في شريحة واحدة.
  static const maxDoneDots = 4;

  /// أقصى عدد نقاط «متبقية» تُعرض فرديًا قبل ضغطها في شريحة واحدة.
  static const maxAheadDots = 6;

  /// يحسب عدد النقاط الفردية وهل تُضاف شريحة مضغوطة لكل جهة — دالة نقية
  /// قابلة للاختبار بمعزل عن الودجت (ق39: نقاط دون أرقام حتى مع طابور طويل).
  static ({int doneDots, bool doneCompressed, int aheadDots, bool aheadCompressed}) segments({
    required int done,
    required int ahead,
  }) {
    final doneCompressed = done > maxDoneDots;
    final aheadCompressed = ahead > maxAheadDots;
    return (
      doneDots: doneCompressed ? maxDoneDots - 1 : done,
      doneCompressed: doneCompressed,
      aheadDots: aheadCompressed ? maxAheadDots - 1 : ahead,
      aheadCompressed: aheadCompressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    final seg = segments(done: done, ahead: ahead);
    return Semantics(
      label: 'تقدّم الطابور',
      container: true,
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: SaloniSpacing.space4,
          vertical: SaloniSpacing.space3,
        ),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          border: Border.all(color: c.line),
          borderRadius: SaloniRadius.lgAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    label ?? 'تقدّم الطابور',
                    overflow: TextOverflow.ellipsis,
                    style: SaloniTextStyles.caption.copyWith(color: c.inkMuted),
                  ),
                ),
                if (updated != null) ...[
                  const SizedBox(width: SaloniSpacing.space2),
                  Flexible(
                    child: Text(
                      'آخر تحديث $updated',
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: SaloniTextStyles.caption.copyWith(color: c.inkMuted),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: SaloniSpacing.space2),
            ExcludeSemantics(
              child: Row(
                children: [
                  // «أدوار منجزة» — الأبعد عن الحالي أولًا، فتُضغط الزيادة في
                  // شريحة واحدة بدل نقاط لا تُرى بعرض 360px (ق39).
                  if (seg.doneCompressed) ...[
                    Expanded(flex: 20, child: _dot(c.primary)),
                    const SizedBox(width: 6),
                  ],
                  for (var i = 0; i < seg.doneDots; i++) ...[
                    Expanded(flex: 10, child: _dot(c.primary)),
                    const SizedBox(width: 6),
                  ],
                  for (var i = 0; i < seg.aheadDots; i++) ...[
                    Expanded(flex: 10, child: _dot(c.line)),
                    const SizedBox(width: 6),
                  ],
                  // «ما زال ينتظر» — الأبعد عن الحالي يُضغط، فالنقاط الفردية
                  // الأقرب لدور الزبون تبقى الأوضح.
                  if (seg.aheadCompressed) ...[
                    Expanded(flex: 20, child: _dot(c.line)),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    flex: 18,
                    child: _dot(c.warning),
                  ),
                ],
              ),
            ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: SaloniSpacing.space2),
                child: Text(
                  note!,
                  style: SaloniTextStyles.caption.copyWith(
                    fontSize: 12,
                    height: 18 / 12,
                    color: c.inkSubtle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color color) => Container(
    height: 8,
    decoration: BoxDecoration(color: color, borderRadius: SaloniRadius.fullAll),
  );
}

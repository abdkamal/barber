import 'package:flutter/material.dart';

import '../icons/saloni_icon_name.dart';
import '../theme/saloni_theme.dart';
import '../tokens/saloni_radius.dart';
import '../tokens/saloni_spacing.dart';
import '../tokens/saloni_typography.dart';

class ImpactItem {
  const ImpactItem({
    required this.name,
    required this.from,
    required this.to,
    this.delta,
    this.notify = false,
    this.pastClosing = false,
  });
  final String name;
  final String from;
  final String to;
  final int? delta;
  final bool notify;
  final bool pastClosing;
}

/// قائمة أثر التغيير على من بعده في الطابور — `ImpactList` في `index.d.ts`.
class ImpactList extends StatelessWidget {
  const ImpactList({super.key, this.title, this.note, required this.items});

  final String? title;
  final String? note;
  final List<ImpactItem> items;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Semantics(
      label: 'أثر التغيير',
      container: true,
      child: Container(
        padding: const EdgeInsets.all(SaloniSpacing.space4),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          border: Border.all(color: c.line),
          borderRadius: SaloniRadius.lgAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title ?? 'سيتأثر بهذا التغيير:',
              style: SaloniTextStyles.body.copyWith(
                color: c.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: SaloniSpacing.space2),
            for (var i = 0; i < items.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: SaloniSpacing.space2),
                decoration: BoxDecoration(
                  border: BorderDirectional(
                    top: i == 0 ? BorderSide.none : BorderSide(color: c.line),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        items[i].name,
                        style: SaloniTextStyles.body.copyWith(color: c.ink),
                      ),
                    ),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            items[i].from,
                            style: SaloniTextStyles.body.copyWith(
                              color: c.inkMuted,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: SaloniIcon(
                              SaloniIconName.caretLeft,
                              size: 14,
                              color: c.inkMuted,
                            ),
                          ),
                          Text(
                            items[i].to,
                            style: SaloniTextStyles.body.copyWith(
                              color: c.inkMuted,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 72,
                      child: Text(
                        items[i].pastClosing
                            ? 'بعد الإغلاق'
                            : '+${items[i].delta ?? 0} د',
                        textAlign: TextAlign.end,
                        style: SaloniTextStyles.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: items[i].pastClosing
                              ? c.danger
                              : (items[i].notify ? c.warning : c.inkMuted),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: SaloniSpacing.space3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SaloniIcon(SaloniIconName.bellRinging, size: 16, color: c.inkMuted),
                    const SizedBox(width: SaloniSpacing.space2),
                    Flexible(
                      child: Text(
                        note!,
                        style: SaloniTextStyles.caption.copyWith(color: c.inkMuted),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

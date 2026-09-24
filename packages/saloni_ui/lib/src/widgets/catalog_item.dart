import 'package:flutter/material.dart';

import '../icons/saloni_icon_name.dart';
import '../theme/saloni_theme.dart';
import '../tokens/saloni_radius.dart';
import '../tokens/saloni_spacing.dart';
import '../tokens/saloni_typography.dart';

enum SaloniCatalogKind { service, product }

/// عنصر في كتالوج الخدمات/المنتجات — `CatalogItem` في `index.d.ts`.
class CatalogItem extends StatelessWidget {
  const CatalogItem({
    super.key,
    required this.kind,
    required this.name,
    required this.price,
    this.currency = 'ر.س',
    this.description,
    this.features = const [],
    this.minutes,
    this.imageProvider,
  });

  final SaloniCatalogKind kind;
  final String name;
  final String price;
  final String currency;
  final String? description;
  final List<String> features;
  final int? minutes;
  final ImageProvider? imageProvider;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    final isProduct = kind == SaloniCatalogKind.product;
    final imgBg = isProduct ? c.steelSoft : c.primarySoft;
    final imgFg = isProduct ? c.steel : c.primary;

    return Semantics(
      container: true,
      label: '$name، $price $currency',
      child: Container(
        padding: const EdgeInsets.all(SaloniSpacing.space4),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          border: Border.all(color: c.line),
          borderRadius: SaloniRadius.lgAll,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: SaloniRadius.mdAll,
              child: Container(
                width: 76,
                height: 76,
                alignment: Alignment.center,
                color: imgBg,
                child: imageProvider != null
                    ? Image(image: imageProvider!, width: 76, height: 76, fit: BoxFit.cover)
                    : SaloniIcon(
                        isProduct ? SaloniIconName.package : SaloniIconName.scissors,
                        size: 28,
                        color: imgFg,
                      ),
              ),
            ),
            const SizedBox(width: SaloniSpacing.space4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontFamily: SaloniFonts.display,
                            fontSize: 16,
                            height: 24 / 16,
                            fontWeight: FontWeight.w600,
                            color: c.ink,
                          ),
                        ),
                      ),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          '$price ',
                          style: TextStyle(
                            fontFamily: SaloniFonts.display,
                            fontWeight: FontWeight.w500,
                            color: c.ink,
                          ),
                        ),
                      ),
                      Text(
                        currency,
                        style: TextStyle(
                          fontFamily: SaloniFonts.display,
                          fontWeight: FontWeight.w500,
                          color: c.ink,
                        ),
                      ),
                    ],
                  ),
                  if (description != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        description!,
                        style: SaloniTextStyles.label.copyWith(
                          color: c.inkMuted,
                          fontWeight: FontWeight.w400,
                          height: 22 / 14,
                        ),
                      ),
                    ),
                  if (features.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: SaloniSpacing.space1),
                      child: Wrap(
                        spacing: SaloniSpacing.space3,
                        runSpacing: SaloniSpacing.space1,
                        children: [
                          for (final f in features)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SaloniIcon(SaloniIconName.check, size: 14, color: c.success),
                                const SizedBox(width: 4),
                                Text(f, style: SaloniTextStyles.caption.copyWith(color: c.ink)),
                              ],
                            ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: SaloniSpacing.space1),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SaloniIcon(
                          isProduct ? SaloniIconName.tag : SaloniIconName.clock,
                          size: 14,
                          color: c.inkMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isProduct ? 'متوفر في الصالون' : 'نحو ${minutes ?? 0} دقيقة',
                          style: TextStyle(fontSize: 12, height: 18 / 12, color: c.inkMuted),
                        ),
                      ],
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

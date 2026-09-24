import 'package:flutter/material.dart';

import '../icons/saloni_icon_name.dart';
import '../theme/saloni_theme.dart';
import '../tokens/saloni_spacing.dart';
import '../tokens/saloni_typography.dart';

enum SaloniConnectionState { online, syncing, offline }

/// شريط حالة الاتصال — `ConnectionBar` في `index.d.ts`.
class ConnectionBar extends StatelessWidget {
  const ConnectionBar({
    super.key,
    this.state = SaloniConnectionState.online,
    this.since,
    this.pending = 0,
  });

  final SaloniConnectionState state;
  final String? since;
  final int pending;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    final Color bg;
    final Color fg;
    final String text;
    switch (state) {
      case SaloniConnectionState.online:
        bg = c.successSoft;
        fg = c.success;
        text = 'متصل';
        break;
      case SaloniConnectionState.syncing:
        bg = c.steelSoft;
        fg = c.steel;
        text = 'جارٍ مزامنة $pending إجراء';
        break;
      case SaloniConnectionState.offline:
        bg = c.warningSoft;
        fg = c.warning;
        text =
            'غير متصل منذ ${since ?? ''}${pending > 0 ? ' — $pending إجراء بانتظار المزامنة' : ''}';
        break;
    }

    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: SaloniSpacing.space4,
          vertical: SaloniSpacing.space2,
        ),
        color: bg,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: SaloniSpacing.space2,
          children: [
            SaloniIcon(
              state == SaloniConnectionState.offline
                  ? SaloniIconName.wifiSlash
                  : SaloniIconName.wifiHigh,
              size: 18,
              color: fg,
            ),
            Text(
              text,
              style: SaloniTextStyles.caption.copyWith(
                color: fg,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (state == SaloniConnectionState.offline)
              Text(
                'إضافة زبون حاضر متوقفة',
                style: SaloniTextStyles.caption.copyWith(color: fg),
              ),
          ],
        ),
      ),
    );
  }
}

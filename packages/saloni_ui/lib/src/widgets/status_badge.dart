import 'package:flutter/material.dart';

import '../icons/saloni_icon_name.dart';
import '../theme/saloni_theme.dart';
import '../tokens/saloni_colors.dart';
import '../tokens/saloni_radius.dart';
import '../tokens/saloni_typography.dart';

/// حالات الحجز — `BookingStatus` في `index.d.ts`.
enum BookingStatus {
  waiting,
  called,
  inService,
  done,
  cancelled,
  noShow,
  postponed,
  offered,
  requested,
  walkIn,
  payAwaiting,
  payConfirmed,
}

/// لون شارة الحالة.
enum SaloniTone { neutral, primary, steel, success, warning, danger }

class _StatusSpec {
  const _StatusSpec(this.label, this.tone, this.icon);
  final String label;
  final SaloniTone tone;
  final SaloniIconName? icon;
}

const Map<BookingStatus, _StatusSpec> _kStatus = {
  BookingStatus.waiting: _StatusSpec(
    'بانتظار الدور',
    SaloniTone.neutral,
    SaloniIconName.hourglassMedium,
  ),
  BookingStatus.called: _StatusSpec(
    'اقترب دورك',
    SaloniTone.warning,
    SaloniIconName.bellRinging,
  ),
  BookingStatus.inService: _StatusSpec(
    'في الخدمة',
    SaloniTone.primary,
    SaloniIconName.scissors,
  ),
  BookingStatus.done: _StatusSpec(
    'تمت الخدمة',
    SaloniTone.success,
    SaloniIconName.checkCircle,
  ),
  BookingStatus.cancelled: _StatusSpec(
    'ملغى',
    SaloniTone.danger,
    SaloniIconName.xCircle,
  ),
  BookingStatus.noShow: _StatusSpec(
    'لم يحضر',
    SaloniTone.danger,
    SaloniIconName.xCircle,
  ),
  BookingStatus.postponed: _StatusSpec(
    'مؤجَّل دورًا',
    SaloniTone.warning,
    SaloniIconName.arrowUUpLeft,
  ),
  BookingStatus.offered: _StatusSpec(
    'عرض مؤقت',
    SaloniTone.steel,
    SaloniIconName.hourglassMedium,
  ),
  BookingStatus.requested: _StatusSpec(
    'ساعة محددة',
    SaloniTone.steel,
    SaloniIconName.clock,
  ),
  BookingStatus.walkIn: _StatusSpec(
    'حاضر',
    SaloniTone.neutral,
    SaloniIconName.user,
  ),
  BookingStatus.payAwaiting: _StatusSpec(
    'بانتظار تأكيد الدفع',
    SaloniTone.warning,
    SaloniIconName.coins,
  ),
  BookingStatus.payConfirmed: _StatusSpec(
    'تم تأكيد الدفع',
    SaloniTone.success,
    SaloniIconName.coins,
  ),
};

/// شارة تعرض حالة الحجز: أيقونة + كلمة دائمًا (لا لون وحده).
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.status,
    this.small = false,
    this.label,
    this.tone,
  });

  final BookingStatus status;

  /// حجم صغير (`dw-badge-sm`).
  final bool small;

  /// نص مخصص بدل النص الافتراضي للحالة.
  final String? label;

  /// لون مخصص بدل اللون الافتراضي للحالة.
  final SaloniTone? tone;

  static (Color bg, Color fg) _toneColors(SaloniTone tone, SaloniColors c) {
    switch (tone) {
      case SaloniTone.neutral:
        return (c.surfaceSunken, c.inkMuted);
      case SaloniTone.primary:
        return (c.primarySoft, c.primary);
      case SaloniTone.steel:
        return (c.steelSoft, c.steel);
      case SaloniTone.success:
        return (c.successSoft, c.success);
      case SaloniTone.warning:
        return (c.warningSoft, c.warning);
      case SaloniTone.danger:
        return (c.dangerSoft, c.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = _kStatus[status]!;
    final resolvedTone = tone ?? spec.tone;
    final colors = context.saloniColors;
    final (bg, fg) = _toneColors(resolvedTone, colors);
    final text = label ?? spec.label;
    final iconSize = small ? 14.0 : 16.0;

    return Semantics(
      label: text,
      child: Container(
        height: small ? 24 : 28,
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: small ? 10 : 12,
        ),
        decoration: BoxDecoration(color: bg, borderRadius: SaloniRadius.fullAll),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spec.icon != null) ...[
              SaloniIcon(spec.icon!, size: iconSize, color: fg),
              SizedBox(width: small ? 4 : 6),
            ],
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style:
                    (small
                            ? SaloniTextStyles.caption
                            : SaloniTextStyles.label)
                        .copyWith(color: fg, height: 1, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

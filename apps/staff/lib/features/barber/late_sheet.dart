import 'package:flutter/material.dart';
import 'package:saloni_ui/saloni_ui.dart';

import '../../core/format.dart';
import '../../data/barber_repository.dart';
import '../../data/models.dart';
import '../common/ui.dart';

/// قرار الزبون المتأخر (S-Late؛ ق10، ق21): تأجيل N مرة واحدة / انتظار /
/// «لم يحضر» بعد استخدام التأجيل فقط.
Future<void> showLateSheet(BuildContext context, BarberRepository repo, QueueEntry e) {
  return showSaloniSheet<void>(context, (ctx) => LateSheet(repo: repo, entry: e));
}

class LateSheet extends StatefulWidget {
  const LateSheet({super.key, required this.repo, required this.entry});
  final BarberRepository repo;
  final QueueEntry entry;

  @override
  State<LateSheet> createState() => _LateSheetState();
}

class _LateSheetState extends State<LateSheet> {
  String _steps = '1';
  bool _busy = false;

  Future<void> _do(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      Navigator.of(context).pop();
      toast(context, done);
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    final e = widget.entry;
    final first = e.name.split(' ').first;
    final used = e.postponementUsed;
    // ق23: إعفاء صريح من السيرفر (canPostpone == true) يتيح تأجيلًا جديدًا
    // رغم استخدام التأجيل؛ عدم معرفة الحالة بعد (null) لا يمنع المحاولة —
    // السيرفر يقرر ورفضه يظهر برسالة واضحة.
    final canPostponeAgain = !used || e.canPostpone != false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          SaloniAvatar(name: e.name, size: 45),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$first لم يصل بعد', style: SaloniTextStyles.title2.copyWith(color: c.ink)),
              Text(
                [
                  if (e.calledAt != null) 'استُدعي ${timeAr(e.calledAt!)}',
                  'موعده المتوقع ${timeAr(e.eta)}',
                ].join(' · '),
                style: SaloniTextStyles.caption.copyWith(color: c.inkMuted),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Text(
          !used
              ? 'القرار لك. التأجيل متاح مرة واحدة لهذا الحجز، ويُبلَّغ $first تلقائيًا ويُستدعى التالي.'
              : canPostponeAgain
                  ? 'استُخدم التأجيل، لكن السيرفر أعفى هذا الحجز (تقديم مفاجئ) — يمكنك تأجيله مجددًا.'
                  : 'استُخدم التأجيل لهذا الحجز. يمكنك انتظاره قليلًا أو تسجيله «لم يحضر».',
          style: SaloniTextStyles.body.copyWith(color: c.inkMuted, fontSize: 14),
        ),
        if (canPostponeAgain) ...[
          const SizedBox(height: 14),
          SaloniSegmentedControl(
            label: 'عدد الأدوار',
            value: _steps,
            options: const [
              SaloniSegmentedOption(value: '1', label: 'دور واحد'),
              SaloniSegmentedOption(value: '2', label: 'دوران'),
              SaloniSegmentedOption(value: '3', label: '3 أدوار'),
            ],
            onChanged: (v) => setState(() => _steps = v),
          ),
          const SizedBox(height: 14),
          SaloniButton(
            key: const Key('late-postpone'),
            label: 'تأجيل',
            icon: SaloniIconName.arrowUUpLeft,
            size: SaloniButtonSize.lg,
            block: true,
            onPressed: _busy
                ? null
                : () => _do(() => widget.repo.postpone(e.id, int.parse(_steps)),
                    'تم تأجيل $first وأُبلغ، واستُدعي التالي'),
          ),
        ],
        const SizedBox(height: 14),
        SaloniButton(
          key: const Key('late-wait'),
          label: 'انتظاره قليلًا',
          variant: SaloniButtonVariant.secondary,
          block: true,
          onPressed: _busy ? null : () => _do(() => widget.repo.waitForCustomer(e.id), 'سننتظر $first'),
        ),
        const SizedBox(height: 14),
        SaloniButton(
          key: const Key('late-noshow'),
          label: 'لم يحضر',
          variant: SaloniButtonVariant.danger,
          block: true,
          onPressed: (!used || _busy)
              ? null
              : () => _do(() => widget.repo.markNoShow(e.id), 'سُجّل $first «لم يحضر»'),
        ),
        if (!used) ...[
          const SizedBox(height: 4),
          Text('يُتاح بعد استخدام التأجيل',
              textAlign: TextAlign.center,
              style: SaloniTextStyles.caption.copyWith(color: c.inkSubtle, fontSize: 12)),
        ],
      ],
    );
  }
}

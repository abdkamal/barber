import 'package:flutter/material.dart';
import 'package:saloni_api/saloni_api.dart' as sa;
import 'package:saloni_ui/saloni_ui.dart';

import '../../core/format.dart';
import '../../data/barber_repository.dart';
import '../../data/models.dart';
import '../common/ui.dart';

/// قرار تجاوز الإغلاق لكل حجز متأثر (ق24، design.md §5.8).
class ClosingChoice {
  ClosingChoice(this.bookingId, this.name, this.eta);
  final String bookingId;
  final String name;
  final DateTime? eta;
  sa.ClosingDecision decision = sa.ClosingDecision.serveLate;
  final reason = TextEditingController();
}

/// محرر القرارات — يُستخدم داخل ورقة تعديل الخدمة وورقة تحذير الإغلاق.
class ClosingDecisionsEditor extends StatefulWidget {
  const ClosingDecisionsEditor({super.key, required this.choices});
  final List<ClosingChoice> choices;

  @override
  State<ClosingDecisionsEditor> createState() => _ClosingDecisionsEditorState();
}

class _ClosingDecisionsEditorState extends State<ClosingDecisionsEditor> {
  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SaloniBanner(
          tone: SaloniBannerTone.danger,
          title: 'تجاوز وقت الإغلاق',
          body: 'قرّر لكل حجز: الخدمة بعد الإغلاق، أو الإلغاء مع إبلاغ الزبون بالسبب.',
        ),
        for (final ch in widget.choices) ...[
          const SizedBox(height: 12),
          Text(
            ch.eta == null ? ch.name : '${ch.name} — متوقع ${timeAr(ch.eta!)}',
            style: SaloniTextStyles.bodyStrong.copyWith(color: c.ink),
          ),
          const SizedBox(height: 6),
          SaloniSegmentedControl(
            label: 'قرار ${ch.name}',
            value: ch.decision.toWire(),
            options: const [
              SaloniSegmentedOption(value: 'serve_late', label: 'خدمة بعد الإغلاق'),
              SaloniSegmentedOption(value: 'cancel', label: 'إلغاء مع إبلاغ'),
            ],
            onChanged: (v) => setState(() => ch.decision = sa.ClosingDecision.fromWire(v)),
          ),
          if (ch.decision == sa.ClosingDecision.cancel) ...[
            const SizedBox(height: 8),
            SaloniTextField(
              label: 'السبب (يصل للزبون)',
              controller: ch.reason,
              placeholder: 'تجاوز وقت الإغلاق',
            ),
          ],
        ],
      ],
    );
  }
}

Future<void> submitClosingChoices(BarberRepository repo, List<ClosingChoice> choices) async {
  for (final ch in choices) {
    final reason = ch.reason.text.trim().isEmpty ? 'تجاوز وقت الإغلاق' : ch.reason.text.trim();
    await repo.closingDecision(ch.bookingId, ch.decision, reason);
  }
}

Future<void> showClosingSheet(
  BuildContext context,
  BarberRepository repo,
  List<QueueEntry> affected,
) {
  final choices = [for (final e in affected) ClosingChoice(e.id, e.name, e.eta)];
  return showSaloniSheet<void>(context, (ctx) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClosingDecisionsEditor(choices: choices),
        const SizedBox(height: 16),
        SaloniButton(
          label: 'تأكيد القرارات',
          size: SaloniButtonSize.lg,
          block: true,
          onPressed: () async {
            await submitClosingChoices(repo, choices);
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
        ),
      ],
    );
  });
}

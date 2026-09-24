import 'dart:async';

import 'package:flutter/material.dart';
import 'package:saloni_ui/saloni_ui.dart';

import '../../core/format.dart';
import '../../data/barber_repository.dart';
import '../../data/models.dart';
import '../common/ui.dart';
import 'closing_sheet.dart';

/// تعديل الخدمة أثناء الجلسة مع معاينة الأثر (S-Edit؛ ق9، ق24، design.md §5.7).
Future<void> showEditServicesSheet(BuildContext context, BarberRepository repo, QueueEntry e) {
  return showSaloniSheet<void>(context, (ctx) => EditServicesSheet(repo: repo, entry: e));
}

class EditServicesSheet extends StatefulWidget {
  const EditServicesSheet({super.key, required this.repo, required this.entry});
  final BarberRepository repo;
  final QueueEntry entry;

  @override
  State<EditServicesSheet> createState() => _EditServicesSheetState();
}

class _EditServicesSheetState extends State<EditServicesSheet> {
  late final Set<String> _selected = {...widget.entry.serviceIds};
  ImpactPreview? _preview;
  bool _loading = false;
  String? _previewError;
  Timer? _debounce;
  int _requestId = 0;
  List<ClosingChoice> _choices = const [];
  bool _saving = false;

  bool get _changed {
    final a = widget.entry.serviceIds.toSet();
    return a.length != _selected.length || !a.containsAll(_selected);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _toggle(String id, bool on) {
    setState(() {
      on ? _selected.add(id) : _selected.remove(id);
      _preview = null;
      _choices = const [];
      _previewError = null;
    });
    _debounce?.cancel();
    if (!_changed || _selected.isEmpty) return;
    if (!widget.repo.isOnline) return;
    _debounce = Timer(const Duration(milliseconds: 350), _loadPreview);
  }

  Future<void> _loadPreview() async {
    final id = ++_requestId;
    setState(() => _loading = true);
    try {
      final p = await widget.repo.previewImpact(widget.entry.id, _ordered());
      if (!mounted || id != _requestId) return;
      setState(() {
        _preview = p;
        _choices = [
          for (final i in p.pastClosing) ClosingChoice(i.bookingId, i.name, i.to),
        ];
      });
    } catch (e) {
      if (mounted && id == _requestId) setState(() => _previewError = errorText(e));
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  List<String> _ordered() => [
        for (final s in widget.repo.services)
          if (_selected.contains(s.id)) s.id,
      ];

  Future<void> _confirm() async {
    setState(() => _saving = true);
    await widget.repo.changeServices(widget.entry.id, _ordered());
    await submitClosingChoices(widget.repo, _choices);
    if (!mounted) return;
    Navigator.of(context).pop();
    toast(context, 'تم تعديل الخدمة');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    final repo = widget.repo;
    final e = widget.entry;
    final first = e.name.split(' ').first;
    final notified = _preview?.notified ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('تعديل خدمة $first', style: SaloniTextStyles.title2.copyWith(color: c.ink)),
        const SizedBox(height: 4),
        Text(
          e.actualStart == null
              ? 'لن يُعاد التوقيت من الصفر.'
              : 'الخدمة جارية منذ ${timeAr(e.actualStart!)} — لن يُعاد التوقيت من الصفر.',
          style: SaloniTextStyles.caption.copyWith(color: c.inkMuted),
        ),
        for (final s in repo.services.where((s) => s.active)) ...[
          const SizedBox(height: 14),
          ServiceChip(
            key: Key('svc-${s.id}'),
            name: s.name,
            minutes: s.baseDurationMin,
            price: repo.currency.amount(s.priceCents),
            currency: repo.currency.symbol,
            selected: _selected.contains(s.id),
            onToggle: (on) => _toggle(s.id, on),
          ),
        ],
        const SizedBox(height: 14),
        if (_changed && !repo.isOnline)
          const SaloniBanner(
            tone: SaloniBannerTone.info,
            title: 'معاينة الأثر تحتاج اتصالًا',
            body: 'التعديل يُقبل دائمًا ويُحفظ على جهازك، ويُزامن عند عودة الاتصال؛ '
                'ويُبلَّغ تلقائيًا كل من تغيّر وقته أكثر من 30 دقيقة.',
          ),
        if (_loading) const LinearProgressIndicator(),
        if (_previewError != null) SaloniBanner(tone: SaloniBannerTone.warning, body: _previewError),
        if (_preview != null)
          _preview!.items.isEmpty
              ? const SaloniBanner(tone: SaloniBannerTone.success, body: 'لن يتأثر أحد بعدك بهذا التعديل.')
              : ImpactList(
                  key: const Key('impact-list'),
                  items: [
                    for (final i in _preview!.items)
                      ImpactItem(
                        name: i.name,
                        from: i.from == null ? '—' : hhmm(i.from!),
                        to: i.to == null ? '—' : hhmm(i.to!),
                        delta: i.deltaMin,
                        notify: i.notify,
                        pastClosing: i.pastClosing,
                      ),
                  ],
                  note: notified.isEmpty
                      ? null
                      : 'سيصل تنبيه لـ${notified.map((i) => i.name.split(' ').first).join(' و')} '
                          'لأن وقته تغيّر أكثر من 30 دقيقة',
                ),
        if (_choices.isNotEmpty) ...[
          const SizedBox(height: 14),
          ClosingDecisionsEditor(choices: _choices),
        ],
        const SizedBox(height: 20),
        SaloniButton(
          key: const Key('confirm-edit'),
          label: 'تأكيد التعديل',
          size: SaloniButtonSize.lg,
          block: true,
          loading: _saving,
          onPressed: (!_changed || _selected.isEmpty || _saving || _loading) ? null : _confirm,
        ),
        const SizedBox(height: 10),
        SaloniButton(
          label: 'تراجع',
          variant: SaloniButtonVariant.ghost,
          block: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

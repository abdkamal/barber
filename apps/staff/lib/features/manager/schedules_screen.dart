import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saloni_ui/saloni_ui.dart';

import '../../core/format.dart';
import '../../core/raw_api.dart';
import '../../state/app_services.dart';
import '../common/shells.dart';
import '../common/ui.dart';
import 'manager_common.dart';

class _Data {
  _Data(this.staff, this.schedules, this.breaks, this.absences);
  final List<Map<String, dynamic>> staff;
  final List<Map<String, dynamic>> schedules;
  final List<Map<String, dynamic>> breaks;
  final List<Map<String, dynamic>> absences;

  String nameOf(String? id) {
    if (id == null || id.isEmpty) return 'الصالون';
    if (id == 'all') return 'كل الحلاقين';
    for (final s in staff) {
      if (str(s, ['id']) == id) return str(s, ['name'], 'حلاق');
    }
    return 'حلاق';
  }
}

/// أسماء الأيام بترقيم السيرفر (الأحد = 0).
String serverWeekdayAr(int w) =>
    weekdaysFromSaturday.firstWhere((d) => serverWeekday(d.$1) == w, orElse: () => (0, '—')).$2;

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// الدوام والاستراحات والإجازات وفترات الحاضرين فقط (ق26، ق30، ق31، ق33).
class SchedulesScreen extends ConsumerStatefulWidget {
  const SchedulesScreen({super.key});

  @override
  ConsumerState<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends ConsumerState<SchedulesScreen> {
  String _tab = 'hours';
  Key _key = UniqueKey();

  void _reload() => setState(() => _key = UniqueKey());

  Future<_Data> _load() async {
    final api = ref.read(servicesProvider).api;
    final r = await Future.wait([
      api.getManagerStaff(),
      api.getManagerSchedules(),
      api.getManagerBreaks(),
      api.getManagerAbsences(),
    ]);
    return _Data(listOf(r[0]), listOf(r[1]), listOf(r[2]), listOf(r[3]));
  }

  Future<void> _run(Future<void> Function() f, [String? done]) async {
    try {
      await f();
      if (done != null && mounted) toast(context, done);
      _reload();
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    }
  }

  // ---------------- الدوام ----------------

  Future<void> _editHours(_Data d, {String? staffId, int? weekday, String? opens, String? closes}) async {
    var who = staffId;
    var day = weekday ?? 6;
    var from = _parse(opens) ?? 10 * 60;
    var to = _parse(closes) ?? 23 * 60;
    final ok = await showSaloniSheet<bool>(context, (ctx) {
      return StatefulBuilder(builder: (ctx, setState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SectionTitle('ساعات العمل'),
            const SizedBox(height: 6),
            const Muted('إن كان الإغلاق قبل الافتتاح فالدوام يمتد بعد منتصف الليل (ق30).'),
            const SizedBox(height: 12),
            _WhoPicker(
              data: d,
              value: who,
              allowSalon: true,
              onChanged: (v) => setState(() => who = v),
            ),
            const SizedBox(height: 12),
            _DayPicker(value: day, onChanged: (v) => setState(() => day = v)),
            const SizedBox(height: 12),
            _TimeRange(
              from: from,
              to: to,
              onFrom: (v) => setState(() => from = v),
              onTo: (v) => setState(() => to = v),
            ),
            const SizedBox(height: 20),
            SaloniButton(label: 'حفظ', size: SaloniButtonSize.lg, block: true, onPressed: () => Navigator.of(ctx).pop(true)),
          ],
        );
      });
    });
    if (ok != true) return;
    if (from == to) {
      if (mounted) toast(context, 'الافتتاح والإغلاق متساويان');
      return;
    }
    await _run(() async {
      await ref.read(servicesProvider).raw.putSchedule(
            staffId: who,
            weekday: day,
            opensAt: wireTime(from),
            closesAt: wireTime(to),
          );
    }, 'حُفظ الدوام');
  }

  int? _parse(String? hhmm) {
    if (hhmm == null || !hhmm.contains(':')) return null;
    final p = hhmm.split(':');
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  // ---------------- الاستراحات ----------------

  Future<void> _addBreak(_Data d) async {
    String who = 'all';
    var type = 'rest';
    var daily = true;
    var date = DateTime.now();
    var from = 13 * 60;
    var to = 13 * 60 + 30;
    final ok = await showSaloniSheet<bool>(context, (ctx) {
      return StatefulBuilder(builder: (ctx, setState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SectionTitle('استراحة أو فترة جديدة'),
            const SizedBox(height: 12),
            SaloniSegmentedControl(
              label: 'النوع',
              value: type,
              options: const [
                SaloniSegmentedOption(value: 'rest', label: 'راحة'),
                SaloniSegmentedOption(value: 'prayer', label: 'صلاة'),
                SaloniSegmentedOption(value: 'walk_in_only', label: 'حاضرون فقط'),
              ],
              onChanged: (v) => setState(() => type = v),
            ),
            if (type == 'walk_in_only') ...[
              const SizedBox(height: 8),
              const Muted('لا تُقبل فيها حجوزات التطبيق، ويخدم الحلاق زبائن حاضرين (ق33).'),
            ],
            const SizedBox(height: 12),
            _WhoPicker(data: d, value: who, allowAll: true, onChanged: (v) => setState(() => who = v ?? 'all')),
            const SizedBox(height: 12),
            SaloniSegmentedControl(
              label: 'التكرار',
              value: daily ? 'daily' : 'date',
              options: const [
                SaloniSegmentedOption(value: 'daily', label: 'يوميًا'),
                SaloniSegmentedOption(value: 'date', label: 'يوم محدد'),
              ],
              onChanged: (v) => setState(() => daily = v == 'daily'),
            ),
            if (!daily) ...[
              const SizedBox(height: 12),
              SaloniButton(
                label: 'التاريخ: ${digits(_date(date))}',
                icon: SaloniIconName.calendarCheck,
                variant: SaloniButtonVariant.secondary,
                block: true,
                onPressed: () async {
                  final p = await showDatePicker(
                    context: ctx,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDate: date,
                  );
                  if (p != null) setState(() => date = p);
                },
              ),
            ],
            const SizedBox(height: 12),
            _TimeRange(from: from, to: to, onFrom: (v) => setState(() => from = v), onTo: (v) => setState(() => to = v)),
            const SizedBox(height: 20),
            SaloniButton(label: 'إضافة', size: SaloniButtonSize.lg, block: true, onPressed: () => Navigator.of(ctx).pop(true)),
          ],
        );
      });
    });
    if (ok != true) return;
    DateTime at(int m) => DateTime(date.year, date.month, date.day, m ~/ 60, m % 60);
    final end = to > from ? at(to) : at(to).add(const Duration(days: 1));
    await _run(() async {
      await ref.read(servicesProvider).api.upsertManagerBreak({
        'staffId': who,
        'type': type,
        if (daily) ...{'startTime': wireTime(from), 'endTime': wireTime(to)},
        if (!daily) ...{
          'workDate': _date(date),
          'startsAt': at(from).toUtc().toIso8601String(),
          'endsAt': end.toUtc().toIso8601String(),
        },
      });
    }, 'أُضيفت');
  }

  // ---------------- الإجازات ----------------

  Future<void> _addAbsence(_Data d) async {
    final barbers = d.staff.where((s) => s['active'] != false).toList();
    if (barbers.isEmpty) return;
    String? who = str(barbers.first, ['id']);
    var date = DateTime.now();
    final reason = TextEditingController();
    final ok = await showSaloniSheet<bool>(context, (ctx) {
      return StatefulBuilder(builder: (ctx, setState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SectionTitle('إجازة / غياب'),
            const SizedBox(height: 6),
            const Muted('يتوقف الحجز عند الحلاق في ذلك اليوم. الحجوزات القائمة تُنقل يدويًا من «الطوابير» (ق25).'),
            const SizedBox(height: 12),
            _WhoPicker(data: d, value: who, onChanged: (v) => setState(() => who = v)),
            const SizedBox(height: 12),
            SaloniButton(
              label: 'التاريخ: ${digits(_date(date))}',
              icon: SaloniIconName.calendarCheck,
              variant: SaloniButtonVariant.secondary,
              block: true,
              onPressed: () async {
                final p = await showDatePicker(
                  context: ctx,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDate: date,
                );
                if (p != null) setState(() => date = p);
              },
            ),
            const SizedBox(height: 12),
            SaloniTextField(label: 'السبب (اختياري)', controller: reason),
            const SizedBox(height: 20),
            SaloniButton(label: 'تسجيل', size: SaloniButtonSize.lg, block: true, onPressed: () => Navigator.of(ctx).pop(true)),
          ],
        );
      });
    });
    if (ok != true || who == null) return;
    await _run(() async {
      await ref.read(servicesProvider).api.upsertManagerAbsence({
        'staffId': who,
        'workDate': _date(date),
        'reason': reason.text.trim().isEmpty ? null : reason.text.trim(),
      });
    }, 'سُجّلت الإجازة');
  }

  @override
  Widget build(BuildContext context) {
    final raw = ref.read(servicesProvider).raw;
    return DetailScaffold(
      title: 'الدوام والاستراحات',
      subtitle: 'ساعات العمل، الاستراحات، الإجازات',
      body: AsyncView<_Data>(
        key: _key,
        load: _load,
        builder: (context, d, reload) {
          final c = context.saloniColors;
          final children = <Widget>[
            SaloniSegmentedControl(
              label: 'القسم',
              value: _tab,
              options: const [
                SaloniSegmentedOption(value: 'hours', label: 'الدوام'),
                SaloniSegmentedOption(value: 'breaks', label: 'الاستراحات'),
                SaloniSegmentedOption(value: 'absences', label: 'الإجازات'),
              ],
              onChanged: (v) => setState(() => _tab = v),
            ),
          ];
          if (_tab == 'hours') {
            final groups = <String?, List<Map<String, dynamic>>>{};
            for (final s in d.schedules) {
              final id = str(s, ['staffId']);
              groups.putIfAbsent(id.isEmpty ? null : id, () => []).add(s);
            }
            if (groups.isEmpty) children.add(const Muted('لم تُضبط ساعات العمل بعد.'));
            for (final g in groups.entries) {
              final rows = g.value..sort((a, b) => (intOf(a, ['weekday']) ?? 0).compareTo(intOf(b, ['weekday']) ?? 0));
              children.add(Section(
                title: g.key == null ? 'دوام الصالون (الافتراضي)' : d.nameOf(g.key),
                children: [
                  GroupBox(children: [
                    for (var i = 0; i < rows.length; i++)
                      ValueRow(
                        first: i == 0,
                        label: serverWeekdayAr(intOf(rows[i], ['weekday']) ?? 0),
                        value:
                            '${displayWireTime(str(rows[i], ['opensAt']))} – ${displayWireTime(str(rows[i], ['closesAt']))}',
                        onTap: () => _editHours(d,
                            staffId: g.key,
                            weekday: intOf(rows[i], ['weekday']),
                            opens: str(rows[i], ['opensAt']),
                            closes: str(rows[i], ['closesAt'])),
                      ),
                  ]),
                ],
              ));
            }
            children.add(SaloniButton(
              label: 'إضافة / تعديل يوم',
              icon: SaloniIconName.plus,
              variant: SaloniButtonVariant.ghost,
              block: true,
              onPressed: () => _editHours(d),
            ));
          } else if (_tab == 'breaks') {
            if (d.breaks.isEmpty) children.add(const Muted('لا استراحات مسجلة.'));
            for (final b in d.breaks) {
              children.add(SurfaceCard(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${breakTypeAr(str(b, ['type']))} · ${d.nameOf(str(b, ['staffId']))}',
                          style: SaloniTextStyles.bodyStrong.copyWith(color: c.ink)),
                      Muted('${breakWhen(b)} · ${breakTimes(b)}'),
                    ]),
                  ),
                  IconButton(
                    tooltip: 'حذف',
                    onPressed: () => _run(() async => raw.deleteBreak(str(b, ['id'])), 'حُذفت'),
                    icon: SaloniIcon(SaloniIconName.x, color: c.inkMuted),
                  ),
                ]),
              ));
            }
            children.add(SaloniButton(
              label: 'إضافة استراحة أو فترة حاضرين',
              icon: SaloniIconName.plus,
              variant: SaloniButtonVariant.ghost,
              block: true,
              onPressed: () => _addBreak(d),
            ));
          } else {
            if (d.absences.isEmpty) children.add(const Muted('لا إجازات مسجلة.'));
            for (final a in d.absences) {
              children.add(SurfaceCard(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${d.nameOf(str(a, ['staffId']))} · ${digits(str(a, ['workDate']))}',
                          style: SaloniTextStyles.bodyStrong.copyWith(color: c.ink)),
                      if (str(a, ['reason']).isNotEmpty) Muted(str(a, ['reason'])),
                    ]),
                  ),
                  IconButton(
                    tooltip: 'حذف',
                    onPressed: () => _run(() async => raw.deleteAbsence(str(a, ['id'])), 'حُذفت'),
                    icon: SaloniIcon(SaloniIconName.x, color: c.inkMuted),
                  ),
                ]),
              ));
            }
            children.add(SaloniButton(
              label: 'تسجيل إجازة أو غياب',
              icon: SaloniIconName.plus,
              variant: SaloniButtonVariant.ghost,
              block: true,
              onPressed: () => _addAbsence(d),
            ));
          }
          return PageBody(onRefresh: reload, gap: 12, children: children);
        },
      ),
    );
  }
}

/// اختيار الحلاق (أو الصالون/الكل).
class _WhoPicker extends StatelessWidget {
  const _WhoPicker({
    required this.data,
    required this.value,
    required this.onChanged,
    this.allowSalon = false,
    this.allowAll = false,
  });
  final _Data data;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool allowSalon;
  final bool allowAll;

  @override
  Widget build(BuildContext context) {
    final options = <(String?, String)>[
      if (allowSalon) (null, 'الصالون (افتراضي للجميع)'),
      if (allowAll) ('all', 'كل الحلاقين'),
      for (final s in data.staff.where((s) => s['active'] != false)) (str(s, ['id']), str(s, ['name'], 'حلاق')),
    ];
    return GroupBox(children: [
      for (var i = 0; i < options.length; i++)
        ValueRow(
          first: i == 0,
          label: options[i].$2,
          value: options[i].$1 == value ? '✓' : '',
          onTap: () => onChanged(options[i].$1),
        ),
    ]);
  }
}

class _DayPicker extends StatelessWidget {
  const _DayPicker({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final d in weekdaysFromSaturday)
        SaloniButton(
          label: d.$2,
          size: SaloniButtonSize.sm,
          variant: serverWeekday(d.$1) == value ? SaloniButtonVariant.primary : SaloniButtonVariant.secondary,
          onPressed: () => onChanged(serverWeekday(d.$1)),
        ),
    ]);
  }
}

class _TimeRange extends StatelessWidget {
  const _TimeRange({required this.from, required this.to, required this.onFrom, required this.onTo});
  final int from;
  final int to;
  final ValueChanged<int> onFrom;
  final ValueChanged<int> onTo;

  Future<void> _pick(BuildContext context, int m, ValueChanged<int> cb) async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60));
    if (t != null) cb(t.hour * 60 + t.minute);
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: SaloniButton(
          label: 'من ${displayWireTime(wireTime(from))}',
          variant: SaloniButtonVariant.secondary,
          onPressed: () => _pick(context, from, onFrom),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: SaloniButton(
          label: 'إلى ${displayWireTime(wireTime(to))}',
          variant: SaloniButtonVariant.secondary,
          onPressed: () => _pick(context, to, onTo),
        ),
      ),
    ]);
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saloni_api/saloni_api.dart' as sa;
import 'package:saloni_ui/saloni_ui.dart';

import '../../core/format.dart';
import '../../state/app_services.dart';
import '../barber/queue_screen.dart' show uiStatus;
import '../common/ui.dart';
import 'manager_barber.dart';
import 'manager_common.dart';

/// طوابير كل الحلاقين + النقل اليدوي (ق25: للمدير فقط).
class QueuesScreen extends ConsumerStatefulWidget {
  const QueuesScreen({super.key});

  @override
  ConsumerState<QueuesScreen> createState() => _QueuesScreenState();
}

class _QueuesScreenState extends ConsumerState<QueuesScreen> {
  List<sa.ManagerBarberQueue>? _barbers;

  /// كل الطاقم (لإظهار من لا دوام له في ورقة النقل مع السبب).
  List<Map<String, dynamic>> _staff = const [];
  Object? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(servicesProvider).api;
      final queues = await api.getManagerQueues();
      List<Map<String, dynamic>>? staff;
      try {
        staff = listOf(await api.getManagerStaff());
      } catch (e, st) {
        debugPrint('[saloni] staff list failed: $e\n$st');
      }
      if (!mounted) return;
      setState(() {
        _barbers = queues.barbers;
        if (staff != null) _staff = staff;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _transfer(sa.Booking booking, sa.ManagerBarberQueue from) async {
    final others = [
      for (final b in _barbers ?? const <sa.ManagerBarberQueue>[])
        if (b.id != from.id) b,
    ];
    final done = await showSaloniSheet<bool>(
      context,
      (ctx) => TransferSheet(
        booking: booking,
        from: from,
        targets: others,
        idle: idleStaff(_staff, _barbers ?? const [], exclude: from.id),
      ),
    );
    if (done != true) await _load();
    if (done == true) {
      if (mounted) toast(context, 'نُقل الحجز وأُبلغ الزبون');
      await _load();
    }
  }

  /// المرحلة 11: المدير يتراجع دائمًا عن «لن أعمل اليوم» لأي حلاق (ولنفسه).
  Future<void> _undoAbsence(sa.ManagerBarberQueue barber) async {
    final ok = await confirmDialog(
      context,
      title: 'إلغاء غياب ${barber.name}؟',
      body: 'يعود يومه إلى وضعه الطبيعي ويُستأنف الحجز عنده من الآن. '
          'الحجوزات التي نقلتها إلى حلاق آخر تبقى حيث هي ولا تعود تلقائيًا.',
      confirm: 'إلغاء الغياب',
    );
    if (!ok || !mounted) return;
    final api = ref.read(servicesProvider).api;
    try {
      final list = await api.getManagerAbsences();
      final workDate = barber.day?.workDate;
      final match = list.whereType<Map>().where(
          (a) => a['staffId'] == barber.id && (workDate == null || a['workDate'] == workDate));
      if (match.isEmpty) {
        if (mounted) toast(context, 'لا غياب مسجّل له اليوم');
      } else {
        await api.deleteManagerAbsence(match.first['id'] as String);
        if (mounted) toast(context, 'عاد ${barber.name} للعمل اليوم — استُؤنف الحجز عنده');
      }
    } catch (e, st) {
      if (mounted) toast(context, 'تعذّر إلغاء الغياب: ${errorText(e, st)}');
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final barbers = _barbers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'الطوابير',
          subtitle: auth.salon?.name ?? 'كل الحلاقين',
          trailing: SaloniButton(
            label: 'طابوري',
            size: SaloniButtonSize.sm,
            variant: SaloniButtonVariant.secondary,
            icon: SaloniIconName.scissors,
            onPressed: () => context.go('/b/queue'),
          ),
        ),
        Expanded(
          child: PageBody(onRefresh: _load, children: [
            const PendingActivationBanner(),
            if (_error != null && barbers == null)
              EmptyState(
                icon: SaloniIconName.wifiSlash,
                title: 'تعذّر تحميل الطوابير',
                body: errorText(_error!),
                action: SaloniButton(
                    label: 'إعادة المحاولة', variant: SaloniButtonVariant.secondary, onPressed: _load),
              ),
            if (barbers == null && _error == null)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
            if (barbers != null && barbers.isEmpty)
              const EmptyState(
                icon: SaloniIconName.usersThree,
                title: 'لا حلاقين بعد',
                body: 'أضف الطاقم من الإعدادات ← الطاقم.',
              ),
            for (final b in barbers ?? const <sa.ManagerBarberQueue>[]) _BarberQueue(barber: b, onTransfer: _transfer, onUndoAbsence: _undoAbsence),
            if (barbers != null) ..._idleNote(idleStaff(_staff, barbers)),
          ]),
        ),
      ],
    );
  }
}

/// من لا يظهر في الطوابير لأنه بلا دوام اليوم — بدل أن يختفي بلا تفسير.
List<Widget> _idleNote(List<Map<String, dynamic>> idle) {
  if (idle.isEmpty) return const [];
  final names = idle
      .map((s) => str(s, ['role']) == 'manager' ? '${str(s, ['name'])} (مدير)' : str(s, ['name']))
      .join('، ');
  final hasManager = idle.any((s) => str(s, ['role']) == 'manager');
  return [
    Muted(
      'بلا دوام اليوم (لا يُحجز عندهم ولا يُنقل إليهم): $names.'
      '${hasManager ? ' دوام الصالون لا يسري على المديرين — من يحلق منهم يعمل بدوام الصالون من «طابوري» أو يُضبط دوامه من «الدوام».' : ''}',
      key: const Key('idle-staff-note'),
    ),
  ];
}

class _BarberQueue extends StatelessWidget {
  const _BarberQueue({required this.barber, required this.onTransfer, required this.onUndoAbsence});
  final sa.ManagerBarberQueue barber;
  final void Function(sa.Booking booking, sa.ManagerBarberQueue from) onTransfer;
  final void Function(sa.ManagerBarberQueue barber) onUndoAbsence;

  @override
  Widget build(BuildContext context) {
    final state = barber.day?.state;
    final active = barber.queue.where((q) => q.isActive).toList();
    return Section(
      title: barber.name.isEmpty ? 'حلاق' : barber.name,
      trailing: barber.day == null ? const Muted('خارج الدوام') : DayStateBadge(state: state),
      children: [
        if (state == sa.BarberDayState.absentToday)
          SaloniBanner(
            tone: SaloniBannerTone.warning,
            title: 'لن يعمل اليوم — الحجز متوقف عنده',
            body: active.isNotEmpty
                ? 'انقل حجوزاته القائمة يدويًا إلى حلاق آخر — يُبلَّغ الزبائن تلقائيًا. '
                    'وإن كان سيعمل فألغِ الغياب.'
                : 'إن كان سيعمل اليوم فألغِ الغياب.',
            action: SaloniButton(
              key: Key('undo-absence-${barber.id}'),
              label: 'إلغاء الغياب',
              size: SaloniButtonSize.sm,
              variant: SaloniButtonVariant.secondary,
              onPressed: () => onUndoAbsence(barber),
            ),
          ),
        if (state == sa.BarberDayState.disconnected)
          const SaloniBanner(
            tone: SaloniBannerTone.warning,
            body: 'تطبيق الحلاق منقطع — الأوقات تقديرية حتى يعود الاتصال.',
          ),
        if (active.isEmpty) const Muted('لا حجوزات قائمة.'),
        for (var i = 0; i < active.length; i++)
          QueueItem(
            position: i + 1,
            name: active[i].customerName ?? 'زبون',
            services: active[i].services.isEmpty ? 'خدمة' : active[i].serviceNames,
            eta: hhmm((active[i].eta ?? active[i].originalEta).toLocal()),
            duration: active[i].durationMin == null ? null : minutesAr(active[i].durationMin!),
            status: uiStatus(active[i].status),
            walkIn: active[i].walkIn,
            requested: active[i].kind == sa.BookingKind.requested,
            action: active[i].status == sa.BookingStatus.inService
                ? null
                : SaloniButton(
                    key: Key('transfer-${active[i].id}'),
                    label: 'نقل',
                    size: SaloniButtonSize.sm,
                    variant: SaloniButtonVariant.secondary,
                    onPressed: () => onTransfer(active[i], barber),
                  ),
          ),
      ],
    );
  }
}

/// ورقة النقل اليدوي (ق25).
class TransferSheet extends ConsumerStatefulWidget {
  const TransferSheet({
    super.key,
    required this.booking,
    required this.from,
    required this.targets,
    this.idle = const [],
  });
  final sa.Booking booking;
  final sa.ManagerBarberQueue from;
  final List<sa.ManagerBarberQueue> targets;

  /// طاقم نشط بلا دوام اليوم (لا يظهر في `GET /manager/queues`) — يُعرض غير
  /// متاح مع السبب؛ والمدير منهم يمكن منحه دوام الصالون بنقرة (المرحلة 11).
  final List<Map<String, dynamic>> idle;

  @override
  ConsumerState<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<TransferSheet> {
  String? _to;
  bool _busy = false;
  String? _error;
  late List<sa.ManagerBarberQueue> _targets = widget.targets;
  late List<Map<String, dynamic>> _idle = widget.idle;

  /// يمنح مديرًا دوام الصالون ثم يعيد قراءة الطوابير فيصبح هدفًا للنقل.
  Future<void> _adopt(Map<String, dynamic> s) async {
    final id = str(s, ['id']);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(servicesProvider).api;
      final added = await adoptSalonHours(api, id);
      final queues = await api.getManagerQueues();
      if (!mounted) return;
      setState(() {
        _targets = [for (final b in queues.barbers) if (b.id != widget.from.id) b];
        _idle = [for (final x in _idle) if (!_targets.any((t) => t.id == str(x, ['id']))) x];
        if (added == 0) _error = 'لا دوام للصالون لنسخه — اضبط الدوام من «الإعدادات ← الدوام»';
      });
    } catch (e, st) {
      if (mounted) setState(() => _error = errorText(e, st));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  late final String _key = ref.read(servicesProvider).api.newIdempotencyKey();

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(servicesProvider).api.transferBooking(
            bookingId: widget.booking.id,
            toBarberId: _to!,
            idempotencyKey: _key,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on sa.ApiError catch (e) {
      // ق25: لا يتسع وقت الحلاق المختار — نقترح البدائل التي يعيدها السيرفر.
      final alt = e.transferAlternatives;
      final hint = alt.isEmpty
          ? ''
          : '\nمتاح عند: ${alt.map((a) => '${a.barberName} ${timeAr(a.start.toLocal())}').join('، ')}';
      if (mounted) setState(() => _error = '${errorText(e)}$hint');
    } catch (e, st) {
      if (mounted) setState(() => _error = errorText(e, st));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    final name = widget.booking.customerName ?? 'الزبون';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('نقل حجز $name', style: SaloniTextStyles.title2.copyWith(color: c.ink)),
        Text('من ${widget.from.name} إلى:',
            style: SaloniTextStyles.caption.copyWith(color: c.inkMuted)),
        const SizedBox(height: 12),
        if (_targets.isEmpty && _idle.isEmpty) const Muted('لا يوجد حلاق آخر.'),
        for (final t in _targets) ...[
          Builder(builder: (_) {
            final st = t.day?.state;
            final unavailable = t.day == null || st == sa.BarberDayState.absentToday || !t.accepting;
            final reason = t.day == null
                ? 'خارج الدوام'
                : st == sa.BarberDayState.absentToday
                    ? 'غائب اليوم'
                    : (!t.accepting ? 'لا يستقبل الآن' : null);
            return BarberOption(
              name: t.name,
              note: '${digits('${t.queue.where((b) => b.isActive).length}')} في الطابور',
              unavailable: unavailable,
              reason: unavailable ? reason : null,
              selected: _to == t.id,
              onTap: unavailable ? null : () => setState(() => _to = t.id),
            );
          }),
          const SizedBox(height: 8),
        ],
        for (final s in _idle) ...[
          BarberOption(
            key: Key('idle-${str(s, ['id'])}'),
            name: str(s, ['name'], 'حلاق'),
            note: str(s, ['role']) == 'manager' ? 'مدير' : 'حلاق',
            unavailable: true,
            reason: str(s, ['role']) == 'manager' ? ManagerAsBarber.noScheduleReason : 'لا دوام له اليوم',
            selected: false,
            onTap: null,
          ),
          if (str(s, ['role']) == 'manager')
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SaloniButton(
                key: Key('adopt-hours-${str(s, ['id'])}'),
                label: ManagerAsBarber.adoptLabel,
                size: SaloniButtonSize.sm,
                variant: SaloniButtonVariant.ghost,
                onPressed: _busy ? null : () => _adopt(s),
              ),
            ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 6),
        const Muted('يُدرج الحجز عند الحلاق الجديد دون تأخير أحد، ويُبلَّغ الزبون بالنقل ووقته الجديد، وتُسجَّل العملية.'),
        if (_error != null) ...[
          const SizedBox(height: 10),
          SaloniBanner(tone: SaloniBannerTone.danger, body: _error),
        ],
        const SizedBox(height: 16),
        SaloniButton(
          key: const Key('transfer-confirm'),
          label: 'نقل الحجز',
          size: SaloniButtonSize.lg,
          block: true,
          loading: _busy,
          onPressed: (_to == null || _busy) ? null : _submit,
        ),
        const SizedBox(height: 10),
        SaloniButton(
          label: 'تراجع',
          variant: SaloniButtonVariant.ghost,
          block: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}

/// طاقم نشط لا يظهر في `GET /manager/queues` (لا دوام له اليوم) — للعرض في
/// ورقة النقل بسببه بدل أن يختفي بصمت.
List<Map<String, dynamic>> idleStaff(
  List<Map<String, dynamic>> staff,
  List<sa.ManagerBarberQueue> scheduled, {
  String? exclude,
}) {
  final ids = {for (final b in scheduled) b.id};
  return [
    for (final s in staff)
      if (s['active'] != false && !ids.contains(str(s, ['id'])) && str(s, ['id']) != exclude) s,
  ];
}

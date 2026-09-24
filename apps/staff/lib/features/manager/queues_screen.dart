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
import 'manager_common.dart';

/// طوابير كل الحلاقين + النقل اليدوي (ق25: للمدير فقط).
class QueuesScreen extends ConsumerStatefulWidget {
  const QueuesScreen({super.key});

  @override
  ConsumerState<QueuesScreen> createState() => _QueuesScreenState();
}

class _QueuesScreenState extends ConsumerState<QueuesScreen> {
  List<sa.ManagerBarberQueue>? _barbers;
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
      final queues = await ref.read(servicesProvider).api.getManagerQueues();
      if (!mounted) return;
      setState(() {
        _barbers = queues.barbers;
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
      (ctx) => TransferSheet(booking: booking, from: from, targets: others),
    );
    if (done == true) {
      if (mounted) toast(context, 'نُقل الحجز وأُبلغ الزبون');
      await _load();
    }
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
            for (final b in barbers ?? const <sa.ManagerBarberQueue>[]) _BarberQueue(barber: b, onTransfer: _transfer),
          ]),
        ),
      ],
    );
  }
}

class _BarberQueue extends StatelessWidget {
  const _BarberQueue({required this.barber, required this.onTransfer});
  final sa.ManagerBarberQueue barber;
  final void Function(sa.Booking booking, sa.ManagerBarberQueue from) onTransfer;

  @override
  Widget build(BuildContext context) {
    final state = barber.day?.state;
    final active = barber.queue.where((q) => q.isActive).toList();
    return Section(
      title: barber.name.isEmpty ? 'حلاق' : barber.name,
      trailing: barber.day == null ? const Muted('خارج الدوام') : DayStateBadge(state: state),
      children: [
        if (state == sa.BarberDayState.absentToday && active.isNotEmpty)
          const SaloniBanner(
            tone: SaloniBannerTone.warning,
            title: 'غائب اليوم',
            body: 'انقل حجوزاته القائمة يدويًا إلى حلاق آخر — يُبلَّغ الزبائن تلقائيًا.',
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
  const TransferSheet({super.key, required this.booking, required this.from, required this.targets});
  final sa.Booking booking;
  final sa.ManagerBarberQueue from;
  final List<sa.ManagerBarberQueue> targets;

  @override
  ConsumerState<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<TransferSheet> {
  String? _to;
  bool _busy = false;
  String? _error;
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
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
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
        if (widget.targets.isEmpty) const Muted('لا يوجد حلاق آخر.'),
        for (final t in widget.targets) ...[
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

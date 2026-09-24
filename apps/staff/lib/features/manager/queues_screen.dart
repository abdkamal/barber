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
  List<Map<String, dynamic>>? _barbers;
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
      final raw = await ref.read(servicesProvider).api.getManagerQueues();
      if (!mounted) return;
      setState(() {
        _barbers = listOf(raw);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _transfer(Map<String, dynamic> booking, Map<String, dynamic> from) async {
    final others = [
      for (final b in _barbers ?? const <Map<String, dynamic>>[])
        if (barberId(b) != barberId(from)) b,
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
            for (final b in barbers ?? const <Map<String, dynamic>>[]) _BarberQueue(barber: b, onTransfer: _transfer),
          ]),
        ),
      ],
    );
  }
}

class _BarberQueue extends StatelessWidget {
  const _BarberQueue({required this.barber, required this.onTransfer});
  final Map<String, dynamic> barber;
  final void Function(Map<String, dynamic> booking, Map<String, dynamic> from) onTransfer;

  @override
  Widget build(BuildContext context) {
    final state = dayStateOf(barber);
    final queue = listOf(barber, ['queue', 'bookings']);
    final active = queue.where((q) {
      final s = statusOf(q);
      return s == sa.BookingStatus.waiting || s == sa.BookingStatus.called || s == sa.BookingStatus.inService;
    }).toList();
    return Section(
      title: barberName(barber),
      trailing: DayStateBadge(state: state),
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
            name: str(active[i], ['customerName', 'name'], 'زبون'),
            services: servicesText(active[i]),
            eta: etaText(active[i]),
            duration: intOf(active[i], ['durationMin']) == null
                ? null
                : minutesAr(intOf(active[i], ['durationMin'])!),
            status: uiStatus(statusOf(active[i])),
            walkIn: active[i]['walkIn'] == true,
            requested: active[i]['kind'] == 'requested',
            action: statusOf(active[i]) == sa.BookingStatus.inService
                ? null
                : SaloniButton(
                    key: Key('transfer-${active[i]['id']}'),
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
  final Map<String, dynamic> booking;
  final Map<String, dynamic> from;
  final List<Map<String, dynamic>> targets;

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
            bookingId: widget.booking['id'].toString(),
            toBarberId: _to!,
            idempotencyKey: _key,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    final name = str(widget.booking, ['customerName', 'name'], 'الزبون');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('نقل حجز $name', style: SaloniTextStyles.title2.copyWith(color: c.ink)),
        Text('من ${barberName(widget.from)} إلى:',
            style: SaloniTextStyles.caption.copyWith(color: c.inkMuted)),
        const SizedBox(height: 12),
        if (widget.targets.isEmpty) const Muted('لا يوجد حلاق آخر.'),
        for (final t in widget.targets) ...[
          Builder(builder: (_) {
            final st = dayStateOf(t);
            final unavailable = st == sa.BarberDayState.absentToday;
            final next = DateTime.tryParse(str(t, ['nextAvailableStart']));
            return BarberOption(
              name: barberName(t),
              nextAt: next == null ? null : timeAr(next),
              note: '${digits('${listOf(t, ['queue', 'bookings']).length}')} في الطابور',
              unavailable: unavailable,
              reason: unavailable ? 'غائب اليوم' : null,
              selected: _to == barberId(t),
              onTap: unavailable ? null : () => setState(() => _to = barberId(t)),
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

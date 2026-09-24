import 'dart:async';

import 'package:flutter/material.dart';
import 'package:saloni_api/saloni_api.dart' as core;
import 'package:saloni_ui/saloni_ui.dart' as ui;

import '../../services/customer_api.dart';
import '../../widgets/format.dart';
import '../../widgets/status_mapper.dart';

/// شاشة متابعة الحجز — الحلاق، الخدمات، الحالة، الوقت المتوقع، الاستدعاء،
/// آخر تحديث دائمًا، الحالة الفاترة عند الانقطاع (design.md §10، §5.9، §8).
class TrackScreen extends StatefulWidget {
  const TrackScreen({
    super.key,
    required this.api,
    this.externalRefresh,
    required this.onChangeTime,
    required this.onCancel,
    this.pollInterval = const Duration(seconds: 30),
  });

  final CustomerApi api;

  /// حدث خارجي (رسالة FCM) يطلب تحديثًا فوريًا بدل انتظار الاستطلاع الدوري.
  final Stream<void>? externalRefresh;
  final void Function(core.CurrentBooking current) onChangeTime;
  final void Function(core.CurrentBooking current) onCancel;
  final Duration pollInterval;

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> with WidgetsBindingObserver {
  core.CurrentBooking? _current;
  String? _error;
  bool _loading = true;
  Timer? _timer;
  StreamSubscription<void>? _sub;
  DateTime? _lastMarkedEta;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(widget.pollInterval, (_) => _refresh());
    _sub = widget.externalRefresh?.listen((_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final current = await widget.api.getCurrentBooking();
      if (!mounted) return;
      setState(() {
        _current = current;
        _loading = false;
        _error = null;
      });
      if (_lastMarkedEta != current.eta) {
        _lastMarkedEta = current.eta;
        // «كل عرض لشاشة المتابعة يُبلغ التطبيق السيرفر بما عرضه» — design.md §5.9.
        unawaited(widget.api.markBookingSeen(current.booking.id, current.eta));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('متابعة الحجز')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: ui.EmptyState(
                      icon: ui.SaloniIconName.warning,
                      title: 'تعذّر تحميل حالة حجزك',
                      body: _error,
                      action: ui.SaloniButton(label: 'إعادة المحاولة', onPressed: _refresh),
                    ),
                  )
                : _current == null
                    ? const Center(child: Text('لا يوجد حجز نشط حاليًا'))
                    : _Loaded(
                        current: _current!,
                        onChangeTime: () => widget.onChangeTime(_current!),
                        onCancel: () => widget.onCancel(_current!),
                      ),
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.current, required this.onChangeTime, required this.onCancel});

  final core.CurrentBooking current;
  final VoidCallback onChangeTime;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final booking = current.booking;
    final status = mapBookingStatus(booking.status);
    final changed = current.originalEta != current.eta;
    final canModify = booking.status == core.BookingStatus.waiting ||
        booking.status == core.BookingStatus.offered;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (status == ui.BookingStatus.called)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ui.SaloniBanner(
              tone: ui.SaloniBannerTone.warning,
              title: 'اقترب دورك — توجّه إلى الصالون الآن',
              body: 'مكانك محفوظ حتى تصل.',
            ),
          ),
        if (!current.live)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ui.SaloniBanner(
              tone: ui.SaloniBannerTone.info,
              body: 'سنحدّث وقتك ونرسل لك تنبيهًا فور عودة اتصال الصالون.',
            ),
          ),
        ui.EtaCard(
          eta: formatHourMinute(current.eta),
          ampm: formatAmPm(current.eta),
          status: status,
          requested: booking.kind == core.BookingKind.requested,
          barber: 'حلاقك',
          services: '${booking.serviceIds.length} خدمة',
          updated: formatAgo(current.lastUpdateAt),
          originalEta: changed ? '${formatHourMinute(current.originalEta)} ${formatAmPm(current.originalEta)}' : null,
          reason: changed ? current.lastChangeReason : null,
          live: current.live,
          staleFor: current.live ? null : formatAgo(current.lastUpdateAt),
        ),
        const SizedBox(height: 16),
        ui.QueueProgress(
          done: current.progress.done,
          ahead: current.progress.ahead,
          updated: formatAgo(current.lastUpdateAt),
          note: current.live ? null : 'لم يصلنا تحديث من الصالون — قد يكون الترتيب تغيّر',
        ),
        if (canModify) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ui.SaloniButton(
                  label: 'تعديل الوقت',
                  variant: ui.SaloniButtonVariant.secondary,
                  onPressed: onChangeTime,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ui.SaloniButton(
                  label: 'إلغاء الحجز',
                  variant: ui.SaloniButtonVariant.ghost,
                  onPressed: onCancel,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

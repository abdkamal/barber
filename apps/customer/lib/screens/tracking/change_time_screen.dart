import 'dart:async';

import 'package:flutter/material.dart';
import 'package:saloni_api/saloni_api.dart' as core;
import 'package:saloni_ui/saloni_ui.dart' as ui;

import '../../services/customer_api.dart';
import '../../widgets/format.dart';

/// تعديل وقت الحجز — عملية واحدة: نقل ذري أو عرض أقرب وقت (design.md §5.12).
///
/// إن تعذّرت الساعة المطلوبة يعيد السيرفر `409 SLOT_UNAVAILABLE` مع أقرب وقت
/// محجوز مؤقتًا (`ApiError.changeTimeOffer`) ويبقى الحجز كما هو: القبول
/// `POST /bookings {offerId}` ينقل الحجز نفسه، والرفض يحرر العرض.
class ChangeTimeScreen extends StatefulWidget {
  const ChangeTimeScreen({
    super.key,
    required this.api,
    required this.current,
    required this.onChanged,
  });

  final CustomerApi api;
  final core.CurrentBooking current;
  final ValueChanged<core.Booking> onChanged;

  @override
  State<ChangeTimeScreen> createState() => _ChangeTimeScreenState();
}

class _ChangeTimeScreenState extends State<ChangeTimeScreen> {
  core.BookingKind _kind = core.BookingKind.queue;
  TimeOfDay? _time;
  bool _loading = false;
  String? _error;
  core.Quote? _offer;
  int _secondsLeft = 0;
  Timer? _countdown;

  @override
  void dispose() {
    _countdown?.cancel();
    super.dispose();
  }

  void _showOffer(core.Quote offer) {
    _countdown?.cancel();
    int left() {
      final exp = offer.offerExpiresAt;
      if (exp == null) return 120;
      return exp.difference(DateTime.now().toUtc()).inSeconds.clamp(0, 3600);
    }

    setState(() {
      _offer = offer;
      _secondsLeft = left();
      _error = null;
    });
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      final l = left();
      setState(() => _secondsLeft = l);
      if (l <= 0) {
        t.cancel();
        setState(() {
          _offer = null;
          _error = 'انتهت مدة العرض — حجزك الحالي باقٍ كما هو.';
        });
      }
    });
  }

  Future<void> _acceptOffer() async {
    final offer = _offer;
    if (offer?.offerId == null) return;
    setState(() => _loading = true);
    try {
      final booking = await widget.api.createBooking(offerId: offer!.offerId);
      _countdown?.cancel();
      widget.onChanged(booking);
    } on core.ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _declineOffer() async {
    final offer = _offer;
    _countdown?.cancel();
    setState(() => _offer = null);
    if (offer?.offerId != null) {
      try {
        await widget.api.rejectOffer(offer!.offerId!);
      } catch (_) {
        // يُحرَّر العرض عند انتهاء مدته على أي حال.
      }
    }
  }

  DateTime? get _requestedAtUtc {
    if (_kind != core.BookingKind.requested || _time == null) return null;
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
      _time!.hour,
      _time!.minute,
    ).toUtc();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _submit() async {
    if (_kind == core.BookingKind.requested && _time == null) {
      setState(() => _error = 'اختر الساعة المطلوبة أولًا');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final booking = await widget.api.changeBookingTime(
        bookingId: widget.current.booking.id,
        kind: _kind,
        requestedAt: _requestedAtUtc,
      );
      widget.onChanged(booking);
    } on core.ApiError catch (e) {
      final offer = e.changeTimeOffer;
      if (offer != null && offer.offerId != null) {
        _showOffer(offer);
      } else {
        setState(() => _error = e.message);
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تعديل الوقت')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'موعدك الحالي: ${formatHourMinute(widget.current.eta)} ${formatAmPm(widget.current.eta)}',
              ),
              const SizedBox(height: 16),
              ui.SaloniSegmentedControl(
                label: 'نوع الحجز',
                value: _kind == core.BookingKind.queue ? 'queue' : 'hour',
                options: const [
                  ui.SaloniSegmentedOption(
                    value: 'queue',
                    label: 'أقرب دور',
                    icon: ui.SaloniIconName.listNumbers,
                  ),
                  ui.SaloniSegmentedOption(
                    value: 'hour',
                    label: 'ساعة محددة',
                    icon: ui.SaloniIconName.clock,
                  ),
                ],
                onChanged: (v) => setState(() {
                  _kind = v == 'hour'
                      ? core.BookingKind.requested
                      : core.BookingKind.queue;
                }),
              ),
              if (_kind == core.BookingKind.requested) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _pickTime,
                  child: Text(
                    _time == null
                        ? 'اختر الساعة الجديدة'
                        : _time!.format(context),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                ui.SaloniBanner(tone: ui.SaloniBannerTone.danger, body: _error),
              ],
              if (_offer != null) ...[
                const SizedBox(height: 16),
                ui.OfferCard(
                  requested: _requestedAtUtc == null
                      ? ''
                      : '${formatHourMinute(_requestedAtUtc!)} ${formatAmPm(_requestedAtUtc!)}',
                  offered:
                      '${formatHourMinute(_offer!.start)} ${formatAmPm(_offer!.start)}',
                  barber:
                      _offer!.barberName ??
                      widget.current.barber?.name ??
                      'حلاقك',
                  secondsLeft: _secondsLeft,
                  onAccept: _loading ? null : _acceptOffer,
                  onDecline: _loading ? null : _declineOffer,
                ),
                const SizedBox(height: 8),
                const Text(
                  'الساعة المطلوبة غير متاحة؛ هذا أقرب وقت محجوز لك مؤقتًا، وحجزك الحالي باقٍ كما هو حتى تقبل.',
                ),
              ],
              const SizedBox(height: 24),
              if (_offer == null)
                ui.SaloniButton(
                  label: 'تأكيد التعديل',
                  size: ui.SaloniButtonSize.lg,
                  block: true,
                  loading: _loading,
                  onPressed: _loading ? null : _submit,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

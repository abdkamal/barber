import 'package:flutter/material.dart';
import 'package:saloni_api/saloni_api.dart' as core;
import 'package:saloni_ui/saloni_ui.dart' as ui;

import '../../services/customer_api.dart';
import '../../widgets/format.dart';

/// تعديل وقت الحجز — عملية واحدة: نقل ذري أو عرض أقرب وقت (design.md §5.12).
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

  DateTime? get _requestedAtUtc {
    if (_kind != core.BookingKind.requested || _time == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, _time!.hour, _time!.minute).toUtc();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time ?? TimeOfDay.now());
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
                  ui.SaloniSegmentedOption(value: 'queue', label: 'أقرب دور', icon: ui.SaloniIconName.listNumbers),
                  ui.SaloniSegmentedOption(value: 'hour', label: 'ساعة محددة', icon: ui.SaloniIconName.clock),
                ],
                onChanged: (v) => setState(() {
                  _kind = v == 'hour' ? core.BookingKind.requested : core.BookingKind.queue;
                }),
              ),
              if (_kind == core.BookingKind.requested) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _pickTime,
                  child: Text(_time == null ? 'اختر الساعة الجديدة' : _time!.format(context)),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                ui.SaloniBanner(tone: ui.SaloniBannerTone.danger, body: _error),
              ],
              const SizedBox(height: 24),
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

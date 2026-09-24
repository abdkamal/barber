import 'package:flutter/material.dart';
import 'package:saloni_ui/saloni_ui.dart' as ui;

import '../../services/customer_api.dart';
import '../../widgets/format.dart';

/// شاشة تأكيد الإلغاء — ق29: يُسمح للزبون بالإلغاء في أي وقت قبل بدء خدمته.
Future<void> showCancelSheet({
  required BuildContext context,
  required CustomerApi api,
  required String bookingId,
  required String barberName,
  required DateTime eta,
  required VoidCallback onCancelled,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CancelSheet(
      api: api,
      bookingId: bookingId,
      barberName: barberName,
      eta: eta,
      onCancelled: onCancelled,
    ),
  );
}

class CancelSheet extends StatefulWidget {
  const CancelSheet({
    super.key,
    required this.api,
    required this.bookingId,
    required this.barberName,
    required this.eta,
    required this.onCancelled,
  });

  final CustomerApi api;
  final String bookingId;
  final String barberName;
  final DateTime eta;
  final VoidCallback onCancelled;

  @override
  State<CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<CancelSheet> {
  bool _loading = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.api.cancelBooking(widget.bookingId);
      if (mounted) Navigator.of(context).pop();
      widget.onCancelled();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('إلغاء حجزك اليوم؟', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text(
              'حجزك عند ${widget.barberName} الساعة ${formatHourMinute(widget.eta)} ${formatAmPm(widget.eta)}. '
              'يمكنك الإلغاء في أي وقت قبل بدء خدمتك، ويمكنك الحجز من جديد لاحقًا.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              ui.SaloniBanner(tone: ui.SaloniBannerTone.danger, body: _error),
            ],
            const SizedBox(height: 16),
            ui.SaloniButton(
              label: 'نعم، ألغِ الحجز',
              variant: ui.SaloniButtonVariant.danger,
              size: ui.SaloniButtonSize.lg,
              block: true,
              loading: _loading,
              onPressed: _loading ? null : _confirm,
            ),
            const SizedBox(height: 10),
            ui.SaloniButton(
              label: 'الإبقاء على الحجز',
              variant: ui.SaloniButtonVariant.secondary,
              block: true,
              onPressed: _loading ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

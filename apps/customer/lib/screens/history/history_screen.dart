import 'package:flutter/material.dart';
import 'package:saloni_api/saloni_api.dart' as api;
import 'package:saloni_ui/saloni_ui.dart' as ui;

import '../../services/customer_api.dart';
import '../../widgets/format.dart';
import '../../widgets/status_mapper.dart';

/// السجل والمدفوعات — الزيارات وحالة الدفع («بانتظار تأكيد الدفع» —
/// design.md §10، §2 «payments»).
///
/// **ملاحظة صدق:** شكل عناصر `GET /customer/history` غير مفصَّل حرفيًا في
/// `docs/api.md` (يذكر فقط: "الزيارات والخدمات وحالة الدفع"). القراءة هنا
/// تفترض حقولًا شائعة الأسماء (`date`/`barberName`/`serviceNames`/
/// `priceCents`/`paymentStatus`) مع قيم احتياطية آمنة عند غيابها، ويجب
/// تأكيدها مع فريق السيرفر.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.api, required this.currency});

  final CustomerApi api;
  final String currency;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getCustomerHistory();
  }

  void _retry() => setState(() => _future = widget.api.getCustomerHistory());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('السجل')),
      body: SafeArea(
        child: FutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
                child: ui.EmptyState(
                  icon: ui.SaloniIconName.receipt,
                  title: 'تعذّر تحميل السجل',
                  body: '${snap.error}',
                  action: ui.SaloniButton(label: 'إعادة المحاولة', onPressed: _retry),
                ),
              );
            }
            final items = snap.data ?? [];
            if (items.isEmpty) {
              return const Center(
                child: ui.EmptyState(icon: ui.SaloniIconName.receipt, title: 'لا زيارات بعد'),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _HistoryTile(raw: items[i] as Map<String, dynamic>, currency: widget.currency),
            );
          },
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.raw, required this.currency});

  final Map<String, dynamic> raw;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final barber = raw['barberName'] as String? ?? raw['barber'] as String? ?? '—';
    final services = (raw['serviceNames'] as List?)?.join('، ') ?? raw['services'] as String? ?? '';
    final priceCents = raw['priceCents'] as int? ?? raw['amountCents'] as int? ?? 0;
    final dateStr = raw['date'] as String? ?? raw['createdAt'] as String?;
    final paymentStatusWire = raw['paymentStatus'] as String?;
    final ui.BookingStatus? payTone = paymentStatusWire == null
        ? null
        : mapPaymentStatus(api.PaymentStatus.fromWire(paymentStatusWire));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(barber, style: Theme.of(context).textTheme.titleSmall),
              if (payTone != null) ui.StatusBadge(status: payTone, small: true),
            ],
          ),
          if (services.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(services, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(dateStr ?? '', style: Theme.of(context).textTheme.bodySmall),
              Text(formatPrice(priceCents, currency)),
            ],
          ),
        ],
      ),
    );
  }
}

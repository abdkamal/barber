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
  const HistoryScreen({super.key, required this.api, required this.currency, required this.timezone});

  final CustomerApi api;
  final String currency;
  final String timezone;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<api.HistoryVisit>> _future;

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
        child: FutureBuilder<List<api.HistoryVisit>>(
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
              itemBuilder: (context, i) =>
                  _HistoryTile(visit: items[i], currency: widget.currency, timezone: widget.timezone),
            );
          },
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.visit, required this.currency, required this.timezone});

  final api.HistoryVisit visit;
  final String currency;
  final String timezone;

  @override
  Widget build(BuildContext context) {
    final b = visit.booking;
    final barber = visit.barberName.isEmpty ? '—' : visit.barberName;
    final services = b.services.map((s) => s.name).join('، ');
    final priceCents = visit.payment?.amountCents ?? b.priceCents ?? 0;
    final when = b.actualStart ?? b.eta ?? b.createdAt;
    final dateStr = when == null ? (b.workDate ?? '') : formatVisitDate(when, timezone);
    // حالة الدفع لما اكتملت خدمته، وإلا حالة الزيارة نفسها (ملغى، لم يحضر…).
    final ui.BookingStatus tone = visit.payment != null
        ? mapPaymentStatus(visit.payment!.status)
        : mapBookingStatus(b.status);

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
              Expanded(
                child: Text(barber,
                    style: Theme.of(context).textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              ui.StatusBadge(status: tone, small: true),
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
              Flexible(child: Text(dateStr, style: Theme.of(context).textTheme.bodySmall)),
              const SizedBox(width: 8),
              Text(formatPrice(priceCents, currency)),
            ],
          ),
          // سبب الإلغاء (مثل انتهاء يوم العمل قبل بدء خدمته) إن أرسله السيرفر
          // — design.md §8 «إلغاء بسبب الإغلاق»؛ التنبيه اللحظي يصل بالفعل
          // بإشعار منفصل عند وقوعه، وهذا عرضه لاحقًا في السجل إن توفر.
          if ((b.status == api.BookingStatus.cancelled || b.status == api.BookingStatus.expired) &&
              (b.lastChangeReason ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(b.lastChangeReason!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saloni_ui/saloni_ui.dart';

import '../../core/format.dart';
import '../../state/app_services.dart';
import '../common/ui.dart';

/// تقارير المدير (M-Reports؛ ق15، design.md §9).
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _period = 'd';
  DateTimeRange? _custom;
  Map<String, dynamic>? _data;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) _range() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      'w' => (today.subtract(const Duration(days: 6)), now),
      'm' => (DateTime(now.year, now.month, 1), now),
      'c' when _custom != null => (
          _custom!.start,
          _custom!.end.add(const Duration(days: 1)).subtract(const Duration(seconds: 1))
        ),
      _ => (today, now),
    };
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final (from, to) = _range();
    try {
      final d = await ref.read(servicesProvider).api.getManagerReports(from: from, to: to);
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _custom,
    );
    if (r == null) return;
    setState(() {
      _custom = r;
      _period = 'c';
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final cur = auth.currency;
    final d = _data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(title: 'التقارير', subtitle: auth.salon?.name ?? ''),
        Expanded(
          child: PageBody(onRefresh: _load, children: [
            SaloniSegmentedControl(
              label: 'الفترة',
              value: _period,
              options: const [
                SaloniSegmentedOption(value: 'd', label: 'اليوم'),
                SaloniSegmentedOption(value: 'w', label: 'الأسبوع'),
                SaloniSegmentedOption(value: 'm', label: 'الشهر'),
                SaloniSegmentedOption(value: 'c', label: 'مخصصة'),
              ],
              onChanged: (v) {
                if (v == 'c') {
                  _pickCustom();
                } else {
                  setState(() => _period = v);
                  _load();
                }
              },
            ),
            if (_period == 'c' && _custom != null)
              Muted('${_custom!.start.day}/${_custom!.start.month} – ${_custom!.end.day}/${_custom!.end.month}'),
            if (_loading && d == null)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
            if (_error != null && d == null)
              EmptyState(
                icon: SaloniIconName.wifiSlash,
                title: 'تعذّر تحميل التقارير',
                body: errorText(_error!),
                action: SaloniButton(
                    label: 'إعادة المحاولة', variant: SaloniButtonVariant.secondary, onPressed: _load),
              ),
            if (d != null) ..._content(context, d, cur),
          ]),
        ),
      ],
    );
  }

  List<Widget> _content(BuildContext context, Map<String, dynamic> d, Currency cur) {
    final c = context.saloniColors;
    // شكل `GET /manager/reports` (server/src/reports): revenue{perBarber,total}، visits[]،
    // topServices[]، durationVsBase[]، etaAccuracy[]، peakHours[]، pendingItems{}.
    final revenue = d['revenue'] is Map ? d['revenue'] as Map : const {};
    final total = revenue['total'] is Map ? revenue['total'] as Map : revenue;
    final revPer = listOf(revenue, ['perBarber']);
    final visits = listOf(d, ['visits']);
    final topServices = listOf(d, ['topServices', 'services']);
    final durations = listOf(d, ['durationVsBase']);
    final accuracy = listOf(d, ['etaAccuracy']);
    final peak = listOf(d, ['peakHours']);
    final pending = d['pendingItems'] is Map ? d['pendingItems'] as Map : const {};

    final confirmed = intOf(total, ['confirmed']) ?? 0;
    // سعر السيرفر للمؤكد (مراجعة المرحلة 6) — يختلف عن [confirmed] فقط إن
    // أكّد حلاق مبلغًا غير سعر الخدمة (`payment_confirmed`، AMOUNT_DIFFERS_FROM_PRICE).
    final expectedConfirmed = intOf(total, ['expectedConfirmed']);
    final awaiting = intOf(total, ['awaiting', 'pending']) ?? 0;
    int sum(List<Map<String, dynamic>> l, String k) => l.fold(0, (a, x) => a + (intOf(x, [k]) ?? 0));
    final done = sum(visits, 'done');
    final noShow = sum(visits, 'noShow');
    final cancelled = sum(visits, 'cancelled');
    final postponed = sum(visits, 'postponed');
    // متوسط الانحراف المطلق موزونًا بعدد العينات.
    var samples = 0;
    var weighted = 0.0;
    for (final a in accuracy) {
      final n = intOf(a, ['samples']) ?? 0;
      final m = a['meanAbsMinutes'];
      if (m is num && n > 0) {
        samples += n;
        weighted += m * n;
      }
    }
    final avgDev = samples == 0 ? null : (weighted / samples).round();

    // جدول الحلاقين: زيارات + إيراد مؤكد + متوسط المدة الفعلية.
    final names = <String, String>{};
    for (final l in [revPer, visits, durations]) {
      for (final x in l) {
        names[str(x, ['staffId'])] = str(x, ['staffName'], 'حلاق');
      }
    }
    int? avgDuration(String staffId) {
      var n = 0;
      var t = 0.0;
      for (final x in durations.where((x) => str(x, ['staffId']) == staffId)) {
        final k = intOf(x, ['samples']) ?? 0;
        final m = x['avgActualMinutes'];
        if (m is num && k > 0) {
          n += k;
          t += m * k;
        }
      }
      return n == 0 ? null : (t / n).round();
    }

    Widget cell(String t, {bool head = false}) => Text(
          t,
          style: head
              ? SaloniTextStyles.caption.copyWith(color: c.inkMuted, fontSize: 12)
              : SaloniTextStyles.body.copyWith(color: c.ink, fontSize: 14),
        );
    Widget row(List<String> cells, {bool head = false}) => Container(
          padding: EdgeInsetsDirectional.symmetric(horizontal: 14, vertical: head ? 10 : 12),
          decoration: BoxDecoration(
            border: BorderDirectional(top: head ? BorderSide.none : BorderSide(color: c.line)),
          ),
          child: Row(children: [for (final t in cells) Expanded(child: cell(t, head: head))]),
        );

    final unconfirmed = intOf(pending, ['unconfirmedPayments']) ?? 0;
    final conflicts = intOf(pending, ['syncConflicts']) ?? 0;
    final accounts = intOf(pending, ['pendingAccounts']) ?? 0;
    final disputes = intOf(pending, ['phoneDisputes']) ?? 0;
    // اختلاف بين المبلغ الذي أكده الحلاق وسعر السيرفر (مراجعة المرحلة 6).
    final discrepancies = intOf(pending, ['paymentDiscrepancies']) ?? 0;

    return [
      LayoutBuilder(builder: (context, box) {
        final w = (box.maxWidth - 10) / 2;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
            width: w,
            child: StatTile(
              label: 'الإيراد المؤكد',
              value: cur.amount(confirmed),
              unit: cur.symbol,
              delta: (expectedConfirmed != null && expectedConfirmed != confirmed)
                  ? 'السعر المسجَّل ${cur.format(expectedConfirmed)}'
                  : null,
              deltaTone: (expectedConfirmed != null && expectedConfirmed != confirmed)
                  ? SaloniTone.warning
                  : null,
            ),
          ),
          SizedBox(
            width: w,
            child: StatTile(
              label: 'بانتظار التأكيد',
              value: cur.amount(awaiting),
              unit: cur.symbol,
              deltaTone: SaloniTone.warning,
              delta: unconfirmed == 0 ? null : digits('$unconfirmed دفعة'),
            ),
          ),
          SizedBox(
            width: w,
            child: StatTile(
              label: 'الزيارات المنجزة',
              value: digits('$done'),
              delta: digits('$noShow لم يحضر · $cancelled ملغى · $postponed تأجيل'),
            ),
          ),
          SizedBox(
            width: w,
            child: StatTile(
              label: 'دقة الأوقات المتوقعة',
              value: avgDev == null ? '—' : digits('±$avgDev'),
              unit: avgDev == null ? null : 'د',
              delta: samples == 0 ? 'لا عينات بعد' : digits('$samples زيارة'),
            ),
          ),
        ]);
      }),
      Section(title: 'حسب الحلاق', children: [
        Container(
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            border: Border.all(color: c.line),
            borderRadius: SaloniRadius.lgAll,
          ),
          child: Column(children: [
            row(['الحلاق', 'زيارات', 'الإيراد (${cur.symbol})', 'متوسط المدة'], head: true),
            if (names.isEmpty) row(['—', '—', '—', '—']),
            for (final e in names.entries)
              row([
                e.value,
                digits('${intOf(visits.where((v) => str(v, ['staffId']) == e.key).firstOrNull, ['done']) ?? 0}'),
                cur.amount(intOf(revPer.where((v) => str(v, ['staffId']) == e.key).firstOrNull, ['confirmed']) ?? 0),
                avgDuration(e.key) == null ? '—' : minutesAr(avgDuration(e.key)!),
              ]),
          ]),
        ),
      ]),
      if (topServices.isNotEmpty)
        Section(title: 'الخدمات الأكثر طلبًا', children: [
          GroupBox(children: [
            for (var i = 0; i < topServices.length; i++)
              ValueRow(
                first: i == 0,
                label: str(topServices[i], ['name'], 'خدمة'),
                value: digits('${intOf(topServices[i], ['times', 'count']) ?? 0} مرة'),
              ),
          ]),
        ]),
      if (durations.isNotEmpty)
        Section(title: 'المدة الفعلية مقابل الأساسية', children: [
          GroupBox(children: [
            for (var i = 0; i < durations.length; i++)
              ValueRow(
                first: i == 0,
                label: '${str(durations[i], ['staffName'])} · ${str(durations[i], ['name'])}',
                value:
                    '${minutesAr(intOf(durations[i], ['avgActualMinutes']) ?? 0)} / ${minutesAr(intOf(durations[i], ['avgBaseMinutes']) ?? 0)}',
              ),
          ]),
        ]),
      if (peak.any((p) => (intOf(p, ['count']) ?? 0) > 0))
        Section(title: 'الذروة', children: [
          StatTile(
            label: 'الحجوزات حسب ساعات اليوم',
            value: () {
              final top = peak.reduce((a, b) => (intOf(a, ['count']) ?? 0) >= (intOf(b, ['count']) ?? 0) ? a : b);
              return displayWireTime(wireTime((intOf(top, ['hour']) ?? 0) * 60));
            }(),
            delta: 'أكثر ساعة ازدحامًا',
            series: [for (final p in peak) (intOf(p, ['count']) ?? 0).toDouble()],
          ),
        ]),
      Section(title: 'المعلّقات', children: [
        if (unconfirmed + conflicts + accounts + disputes + discrepancies == 0)
          const SaloniBanner(tone: SaloniBannerTone.success, body: 'لا معلّقات تحتاج قرارك.'),
        if (unconfirmed > 0)
          SaloniBanner(
            tone: SaloniBannerTone.warning,
            title: digits('$unconfirmed دفعة بانتظار التأكيد'),
            body: 'يؤكدها الحلاق من شاشة «الدفعات» عند استلام المبلغ.',
          ),
        if (discrepancies > 0)
          SaloniBanner(
            tone: SaloniBannerTone.warning,
            title: digits('$discrepancies دفعة بمبلغ مختلف عمّا سجّله السيرفر'),
            body: 'أكّد الحلاق مبلغًا غير سعر الخدمة المسجّل — راجع شاشة «الدفعات».',
          ),
        if (accounts > 0)
          SaloniBanner(
            tone: SaloniBannerTone.info,
            title: digits('$accounts حساب ينتظر الاعتماد'),
            action: SaloniButton(
              label: 'الزبائن',
              size: SaloniButtonSize.sm,
              variant: SaloniButtonVariant.secondary,
              onPressed: () => context.push('/m/customers'),
            ),
          ),
        if (disputes > 0)
          SaloniBanner(
            tone: SaloniBannerTone.warning,
            title: digits('$disputes نزاع على رقم هاتف'),
            action: SaloniButton(
              label: 'حلّ النزاع',
              size: SaloniButtonSize.sm,
              variant: SaloniButtonVariant.secondary,
              onPressed: () => context.push('/m/customers'),
            ),
          ),
        if (conflicts > 0)
          SaloniBanner(
            tone: SaloniBannerTone.danger,
            title: digits('$conflicts تعارض مزامنة'),
            body: 'أحداث من أجهزة الحلاقين رُفضت أو تحتاج مراجعة.',
          ),
      ]),
    ];
  }
}

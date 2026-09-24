import 'dart:async';

import 'package:flutter/material.dart';
import 'package:saloni_api/saloni_api.dart' as core;
import 'package:saloni_ui/saloni_ui.dart' as ui;

import '../../services/customer_api.dart';
import '../../widgets/format.dart';
import '../../widgets/onboarding_tip.dart';

enum _Phase { loading, picking, offer, loadError }

/// شاشة الحجز — اختيار خدمة أو أكثر، حلاق معيّن أو «الأسرع»، أقرب دور أو ساعة
/// محددة (design.md §10، §5.3، §5.4).
class BookScreen extends StatefulWidget {
  const BookScreen({
    super.key,
    required this.api,
    required this.currency,
    required this.onBooked,
  });

  final CustomerApi api;
  final String currency;
  final ValueChanged<core.Booking> onBooked;

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  _Phase _phase = _Phase.loading;
  String? _loadErrorMessage;

  List<core.Service> _services = [];
  List<core.Barber> _barbers = [];

  final Set<String> _selectedServiceIds = {};
  String? _selectedBarberId; // null = «الأسرع»
  core.BookingKind _kind = core.BookingKind.queue;
  TimeOfDay? _requestedTime;

  core.Quote? _quote;
  String? _quoteError;
  Timer? _debounce;
  Timer? _countdown;
  int _secondsLeft = 0;
  bool _submitting;
  String? _submitError;

  _BookScreenState() : _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _countdown?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final today = await widget.api.getCustomerToday();
      final services = ((today['services'] as List?) ?? [])
          .map((e) => core.Service.fromJson(e as Map<String, dynamic>))
          .toList();
      final barbers = ((today['barbers'] as List?) ?? [])
          .map((e) => core.Barber.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _services = services;
        _barbers = barbers;
        _phase = _Phase.picking;
      });
    } catch (e) {
      setState(() {
        _loadErrorMessage = '$e';
        _phase = _Phase.loadError;
      });
    }
  }

  DateTime? get _requestedAtUtc {
    if (_kind != core.BookingKind.requested || _requestedTime == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, _requestedTime!.hour, _requestedTime!.minute).toUtc();
  }

  void _onSelectionChanged() {
    _quote = null;
    _quoteError = null;
    _debounce?.cancel();
    if (_selectedServiceIds.isEmpty) {
      setState(() {});
      return;
    }
    if (_kind == core.BookingKind.requested && _requestedTime == null) {
      setState(() {});
      return;
    }
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 350), _fetchQuote);
  }

  Future<void> _fetchQuote() async {
    final requestedAt = _requestedAtUtc;
    try {
      final quote = await widget.api.getQuote(
        serviceIds: _selectedServiceIds.toList(),
        barberId: _selectedBarberId,
        kind: _kind,
        requestedAt: requestedAt,
      );
      if (!mounted) return;
      setState(() {
        _quote = quote;
        _quoteError = null;
      });
      if (quote.isOffer) {
        _startOfferCountdown(quote);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _quoteError = '$e');
    }
  }

  void _startOfferCountdown(core.Quote quote) {
    setState(() => _phase = _Phase.offer);
    _countdown?.cancel();
    final expires = quote.offerExpiresAt;
    _secondsLeft = expires == null ? 120 : expires.difference(DateTime.now().toUtc()).inSeconds.clamp(0, 120);
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _secondsLeft = (_secondsLeft - 1).clamp(0, 120));
      if (_secondsLeft <= 0) {
        t.cancel();
        setState(() {
          _phase = _Phase.picking;
          _quote = null;
        });
      }
    });
  }

  Future<void> _acceptOffer() async {
    final quote = _quote;
    if (quote?.offerId == null) return;
    _countdown?.cancel();
    setState(() => _submitting = true);
    try {
      final booking = await widget.api.createBooking(offerId: quote!.offerId);
      widget.onBooked(booking);
    } catch (e) {
      setState(() => _submitError = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _declineOffer() async {
    final quote = _quote;
    _countdown?.cancel();
    setState(() {
      _phase = _Phase.picking;
      _quote = null;
    });
    if (quote?.offerId != null) {
      try {
        await widget.api.rejectOffer(quote!.offerId!);
      } catch (_) {}
    }
  }

  Future<void> _confirmBooking() async {
    final quote = _quote;
    if (quote == null || quote.isOffer) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final booking = await widget.api.createBooking(
        serviceIds: _selectedServiceIds.toList(),
        barberId: quote.barberId,
        kind: _kind,
        requestedAt: _requestedAtUtc,
      );
      widget.onBooked(booking);
    } catch (e) {
      setState(() => _submitError = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _requestedTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _requestedTime = picked);
      _onSelectionChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('احجز دورك')),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.loading => const Center(child: CircularProgressIndicator()),
          _Phase.loadError => Center(
              child: ui.EmptyState(
                icon: ui.SaloniIconName.warning,
                title: 'تعذّر تحميل بيانات الحجز',
                body: _loadErrorMessage,
                action: ui.SaloniButton(label: 'إعادة المحاولة', onPressed: _load),
              ),
            ),
          _Phase.offer => _buildOfferBody(),
          _ => _buildPickingBody(),
        },
      ),
    );
  }

  Widget _buildOfferBody() {
    final quote = _quote!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_submitError != null) ...[
            ui.SaloniBanner(tone: ui.SaloniBannerTone.danger, body: _submitError),
            const SizedBox(height: 12),
          ],
          ui.OfferCard(
            requested: _requestedTime == null
                ? ''
                : '${formatHourMinute(_requestedAtUtc!)} ${formatAmPm(_requestedAtUtc!)}',
            offered: '${formatHourMinute(quote.start)} ${formatAmPm(quote.start)}',
            barber: _barberName(quote.barberId),
            secondsLeft: _secondsLeft,
            onAccept: _submitting ? null : _acceptOffer,
            onDecline: _submitting ? null : _declineOffer,
          ),
          const SizedBox(height: 16),
          const Text(
            'لا نقدّم أحدًا على من حجز قبله، لذلك نعرض عليك أقرب وقت فعلي بعد الساعة التي طلبتها.',
          ),
        ],
      ),
    );
  }

  String _barberName(String id) {
    final b = _barbers.where((b) => b.id == id).toList();
    return b.isEmpty ? 'أسرع حلاق متاح' : b.first.name;
  }

  Widget _buildPickingBody() {
    final canSubmit = _quote != null && !_quote!.isOffer && !_submitting;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              const OnboardingTip(
                id: 'book_multi_service',
                text: 'يمكنك اختيار أكثر من خدمة، واختيار «الأسرع» ليبدأ حلاقك بأقرب وقت ممكن.',
              ),
              Text('الخدمات', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final s in _services)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ui.ServiceChip(
                    name: s.name,
                    minutes: s.baseDurationMin,
                    price: (s.priceCents / 100).toStringAsFixed(0),
                    currency: widget.currency,
                    selected: _selectedServiceIds.contains(s.id),
                    onToggle: (on) {
                      if (on) {
                        _selectedServiceIds.add(s.id);
                      } else {
                        _selectedServiceIds.remove(s.id);
                      }
                      _onSelectionChanged();
                    },
                  ),
                ),
              const SizedBox(height: 16),
              Text('الحلاق', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ui.BarberOption(
                fastest: true,
                selected: _selectedBarberId == null,
                onTap: () {
                  setState(() => _selectedBarberId = null);
                  _onSelectionChanged();
                },
              ),
              const SizedBox(height: 8),
              for (final b in _barbers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ui.BarberOption(
                    name: b.name,
                    selected: _selectedBarberId == b.id,
                    unavailable: b.nextAvailableStart == null,
                    reason: b.dayState == core.BarberDayState.absentToday
                        ? 'لا يعمل اليوم'
                        : (b.dayState == core.BarberDayState.disconnected ? 'غير متصل' : null),
                    nextAt: b.nextAvailableStart == null ? null : formatHourMinute(b.nextAvailableStart!),
                    wait: b.nextAvailableStart == null
                        ? null
                        : 'بعد ${b.nextAvailableStart!.difference(DateTime.now().toUtc()).inMinutes.clamp(0, 999)} د',
                    onTap: b.nextAvailableStart == null
                        ? null
                        : () {
                            setState(() => _selectedBarberId = b.id);
                            _onSelectionChanged();
                          },
                  ),
                ),
              const SizedBox(height: 16),
              Text('الوقت', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ui.SaloniSegmentedControl(
                label: 'نوع الحجز',
                value: _kind == core.BookingKind.queue ? 'queue' : 'hour',
                options: const [
                  ui.SaloniSegmentedOption(value: 'queue', label: 'أقرب دور', icon: ui.SaloniIconName.listNumbers),
                  ui.SaloniSegmentedOption(value: 'hour', label: 'ساعة محددة', icon: ui.SaloniIconName.clock),
                ],
                onChanged: (v) {
                  setState(() {
                    _kind = v == 'hour' ? core.BookingKind.requested : core.BookingKind.queue;
                  });
                  _onSelectionChanged();
                },
              ),
              if (_kind == core.BookingKind.requested) ...[
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _pickTime,
                  child: Text(_requestedTime == null ? 'اختر الساعة المطلوبة' : _requestedTime!.format(context)),
                ),
              ],
              if (_quoteError != null) ...[
                const SizedBox(height: 12),
                ui.SaloniBanner(tone: ui.SaloniBannerTone.danger, body: _quoteError),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_submitError != null) ...[
                  ui.SaloniBanner(tone: ui.SaloniBannerTone.danger, body: _submitError),
                  const SizedBox(height: 8),
                ],
                if (_quote != null && !_quote!.isOffer) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('الوقت المتوقع'),
                      Text(
                        '${formatHourMinute(_quote!.start)} ${formatAmPm(_quote!.start)}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'نحو ${_quote!.durationMin} دقيقة · ${formatPrice(_quote!.priceCents, widget.currency)} · الدفع في الصالون',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                ],
                ui.SaloniButton(
                  label: 'احجز دوري',
                  size: ui.SaloniButtonSize.lg,
                  block: true,
                  loading: _submitting,
                  onPressed: canSubmit ? _confirmBooking : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

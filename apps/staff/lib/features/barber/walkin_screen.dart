import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saloni_ui/saloni_ui.dart';

import '../../core/format.dart';
import '../../data/barber_repository.dart';
import '../../state/app_services.dart';
import '../common/shells.dart';
import '../common/ui.dart';

/// إضافة زبون حاضر (S-Walkin) — متصل فقط، يُضاف في آخر طابور الحلاق.
class WalkInScreen extends ConsumerStatefulWidget {
  const WalkInScreen({super.key});

  @override
  ConsumerState<WalkInScreen> createState() => _WalkInScreenState();
}

class _WalkInScreenState extends ConsumerState<WalkInScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final Set<String> _services = {};
  bool _busy = false;
  String? _error;
  String? _nameError;
  String? _phoneError;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit(BarberRepository repo) async {
    final digitsOnly = _phone.text.replaceAll(RegExp(r'[^0-9٠-٩]'), '');
    setState(() {
      _nameError = _name.text.trim().isEmpty ? 'أدخل الاسم' : null;
      _phoneError = digitsOnly.length < 8 ? 'أدخل رقم هاتف صحيحًا' : null;
      _error = _services.isEmpty ? 'اختر خدمة واحدة على الأقل' : null;
    });
    if (_nameError != null || _phoneError != null || _error != null) return;
    setState(() => _busy = true);
    try {
      await repo.addWalkIn(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        serviceIds: [for (final s in repo.services) if (_services.contains(s.id)) s.id],
      );
      if (!mounted) return;
      toast(context, 'أُضيف ${_name.text.trim()} إلى آخر طابورك');
      context.canPop() ? context.pop() : context.go('/b/queue');
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(barberRepoProvider);
    final offline = repo.link == LinkStatus.offline;
    return DetailScaffold(
      title: 'إضافة زبون حاضر',
      subtitle: 'يُضاف في آخر طابورك',
      showConnection: true,
      body: PageBody(gap: 16, children: [
        if (offline)
          const SaloniBanner(
            tone: SaloniBannerTone.warning,
            title: 'غير متاح دون اتصال',
            body: 'إضافة زبون حاضر تحتاج اتصالًا بالإنترنت حتى لا يتعارض دوره مع الحجوزات. '
                'حاول عند عودة الاتصال.',
          ),
        SaloniTextField(label: 'الاسم', controller: _name, error: _nameError),
        SaloniTextField(
          label: 'رقم الهاتف',
          controller: _phone,
          prefix: '+966',
          type: SaloniTextFieldType.tel,
          textDirection: TextDirection.ltr,
          error: _phoneError,
        ),
        Section(title: 'الخدمة', children: [
          for (final s in repo.services.where((s) => s.active))
            ServiceChip(
              name: s.name,
              minutes: s.baseDurationMin,
              price: repo.currency.amount(s.priceCents),
              currency: repo.currency.symbol,
              selected: _services.contains(s.id),
              onToggle: (on) => setState(() => on ? _services.add(s.id) : _services.remove(s.id)),
            ),
        ]),
        SaloniBanner(
          tone: SaloniBannerTone.info,
          body: 'الوقت المتوقع لهذا الزبون نحو ${timeAr(repo.estimateNextSlot())}. '
              'إذا ثبّت التطبيق لاحقًا بنفس الرقم، يُربط سجله بحسابه.',
        ),
        if (_error != null) SaloniBanner(tone: SaloniBannerTone.danger, body: _error),
      ]),
      bottom: BottomActions(children: [
        SaloniButton(
          key: const Key('walkin-submit'),
          label: 'إضافة إلى الطابور',
          size: SaloniButtonSize.lg,
          block: true,
          loading: _busy,
          onPressed: (offline || _busy) ? null : () => _submit(repo),
        ),
      ]),
    );
  }
}

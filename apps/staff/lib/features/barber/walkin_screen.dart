import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saloni_api/saloni_api.dart' as sa;
import 'package:saloni_ui/saloni_ui.dart';

import '../../core/format.dart';
import '../../data/barber_repository.dart';
import '../../state/app_services.dart';
import '../common/shells.dart';
import '../common/ui.dart';

/// رسالة «الخدمات» — مطابقة لعنوان القسم الظاهر على الشاشة.
const walkInPickServiceError = 'اختر خدمة واحدة على الأقل من «الخدمات» أعلاه';

/// إضافة زبون حاضر (S-Walkin) — متصل فقط، يُضاف في آخر طابور الحلاق.
///
/// الخدمات من كتالوج الصالون القابل للحجز (`services` في `GET /staff/today`)،
/// اختيار متعدد بمدتها وسعرها، مع مجموع المدة والسعر. إن كان في الصالون خدمة
/// واحدة فقط تُختار تلقائيًا.
class WalkInScreen extends ConsumerStatefulWidget {
  const WalkInScreen({super.key});

  @override
  ConsumerState<WalkInScreen> createState() => _WalkInScreenState();
}

class _WalkInScreenState extends ConsumerState<WalkInScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final Set<String> _services = {};
  bool _autoPicked = false;
  bool _busy = false;
  bool _loadingServices = false;
  String? _servicesLoadError;
  String? _error;
  String? _nameError;
  String? _phoneError;
  String? _serviceError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadServices());
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// الخدمات لم تصل بعد (أول تشغيل مثلًا) — تُطلب من السيرفر مباشرة.
  Future<void> _loadServices() async {
    final repo = ref.read(barberRepoProvider);
    if (repo.services.any((s) => s.active)) return;
    setState(() {
      _loadingServices = true;
      _servicesLoadError = null;
    });
    try {
      await repo.ensureServices();
    } catch (e, st) {
      if (mounted) setState(() => _servicesLoadError = errorText(e, st));
    } finally {
      if (mounted) setState(() => _loadingServices = false);
    }
  }

  void _toggle(String id, bool on) {
    setState(() {
      on ? _services.add(id) : _services.remove(id);
      if (_services.isNotEmpty) _serviceError = null;
    });
  }

  Future<void> _submit(BarberRepository repo, List<sa.Service> catalog) async {
    final digitsOnly = _phone.text.replaceAll(RegExp(r'[^0-9٠-٩]'), '');
    setState(() {
      _error = null;
      _nameError = _name.text.trim().isEmpty ? 'أدخل الاسم' : null;
      _phoneError = digitsOnly.length < 8 ? 'أدخل رقم هاتف صحيحًا' : null;
      _serviceError = _services.isEmpty ? walkInPickServiceError : null;
    });
    if (_nameError != null || _phoneError != null || _serviceError != null) return;
    setState(() => _busy = true);
    try {
      await repo.addWalkIn(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        serviceIds: [for (final s in catalog) if (_services.contains(s.id)) s.id],
      );
      if (!mounted) return;
      toast(context, 'أُضيف ${_name.text.trim()} إلى آخر طابورك');
      context.canPop() ? context.pop() : context.go('/b/queue');
    } catch (e, st) {
      if (mounted) setState(() => _error = errorText(e, st));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(barberRepoProvider);
    final c = context.saloniColors;
    final offline = repo.link == LinkStatus.offline;
    final catalog = [...repo.services.where((s) => s.active)]
      ..sort((a, b) => (a.position ?? 1 << 20).compareTo(b.position ?? 1 << 20));
    // خدمة واحدة في الصالون: تُختار تلقائيًا (مرة واحدة، ويمكن إلغاؤها).
    if (!_autoPicked && catalog.length == 1) {
      _autoPicked = true;
      _services.add(catalog.single.id);
    }
    // خدمة اختيرت ثم أُوقفت من المدير أثناء فتح الشاشة.
    _services.removeWhere((id) => !catalog.any((s) => s.id == id));
    final picked = [for (final s in catalog) if (_services.contains(s.id)) s];
    final totalMin = picked.fold<int>(0, (t, s) => t + s.baseDurationMin);
    final totalPrice = picked.fold<int>(0, (t, s) => t + s.priceCents);
    final noServices = catalog.isEmpty && !_loadingServices;

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
        if (repo.absentToday)
          const SaloniBanner(
            tone: SaloniBannerTone.warning,
            title: 'أنت مسجّل «لن أعمل اليوم»',
            body: 'لا يُضاف زبائن إلى طابورك اليوم. تراجع عن ذلك من «استراحاتي» إن كنت ستعمل.',
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
        Section(
          title: 'الخدمات',
          trailing: catalog.length > 1
              ? Text('اختر واحدة أو أكثر', style: SaloniTextStyles.caption.copyWith(color: c.inkMuted))
              : null,
          children: [
            if (_loadingServices)
              const Center(
                key: Key('walkin-services-loading'),
                child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
              ),
            if (noServices)
              SaloniBanner(
                key: const Key('walkin-no-services'),
                tone: SaloniBannerTone.warning,
                title: 'لا خدمات متاحة',
                body: _servicesLoadError ??
                    'لم تُضف خدمات للصالون بعد، أو كلها موقوفة. يضيفها المدير من «الصالون» ← الخدمات.',
                action: SaloniButton(
                  label: 'إعادة التحميل',
                  size: SaloniButtonSize.sm,
                  variant: SaloniButtonVariant.secondary,
                  onPressed: _loadServices,
                ),
              ),
            for (final s in catalog)
              ServiceChip(
                key: Key('walkin-service-${s.id}'),
                name: s.name,
                minutes: s.baseDurationMin,
                price: repo.currency.amount(s.priceCents),
                currency: repo.currency.symbol,
                selected: _services.contains(s.id),
                onToggle: (on) => _toggle(s.id, on),
              ),
            if (picked.isNotEmpty)
              SurfaceCard(
                key: const Key('walkin-total'),
                child: Row(children: [
                  SaloniIcon(SaloniIconName.clock, color: c.inkMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      picked.length == 1 ? 'خدمة واحدة' : '${digits('${picked.length}')} خدمات',
                      style: SaloniTextStyles.bodyStrong.copyWith(color: c.ink),
                    ),
                  ),
                  Text(
                    '${minutesAr(totalMin)} · ${repo.currency.amount(totalPrice)} ${repo.currency.symbol}',
                    style: SaloniTextStyles.bodyStrong.copyWith(color: c.ink),
                  ),
                ]),
              ),
            if (_serviceError != null)
              Text(
                _serviceError!,
                key: const Key('walkin-service-error'),
                style: SaloniTextStyles.caption.copyWith(color: c.danger),
              ),
          ],
        ),
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
          onPressed: (offline || _busy || noServices || repo.absentToday)
              ? null
              : () => _submit(repo, catalog),
        ),
      ]),
    );
  }
}

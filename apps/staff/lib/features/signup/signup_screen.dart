import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saloni_api/saloni_api.dart' show SaloniCurrency, serverWeekday;
import 'package:saloni_ui/saloni_ui.dart';

import '../../core/format.dart';
import '../../core/help_texts.dart';
import '../../state/app_services.dart';
import '../common/ui.dart';

/// العملات المتاحة عند إنشاء الصالون (ق34، ق41) — من التعريف المشترك، مع
/// منطقة زمنية مقترحة لكل منها. **بلا أعلام**: رمز العملة هو علامتها.
final List<SaloniCurrency> signupCurrencies = [
  for (final c in SaloniCurrency.supported)
    if (c.defaultTimezone != null) c,
];

/// منطقة الصالون الزمنية (تُعرض بها كل الأوقات — design.md §2). تُقترح من
/// العملة ويمكن تغييرها: العملة لا تحدد البلد دائمًا (مثلًا الدينار الأردني أو
/// الشيكل في فلسطين، والأردن وفلسطين بتوقيتين مختلفين شتاءً).
const signupRegions = [
  ('Asia/Riyadh', 'السعودية'),
  ('Asia/Dubai', 'الإمارات'),
  ('Asia/Kuwait', 'الكويت'),
  ('Asia/Qatar', 'قطر'),
  ('Asia/Bahrain', 'البحرين'),
  ('Asia/Muscat', 'عُمان'),
  ('Asia/Amman', 'الأردن'),
  ('Asia/Hebron', 'فلسطين — الضفة'),
  ('Asia/Gaza', 'فلسطين — غزة'),
  ('Asia/Jerusalem', 'القدس'),
  ('Africa/Cairo', 'مصر'),
];

class _Day {
  _Day(this.weekday, this.name);
  final int weekday;
  final String name;
  bool open = true;
  int from = 10 * 60;
  int to = 23 * 60;
}

class _NewService {
  _NewService(this.name, this.minutes, this.priceText);
  final String name;
  final int minutes;
  final String priceText;
}

/// تسجيل صالون جديد (ق37، design.md §10): بيانات صاحب الصالون ← ملف الصالون ←
/// ساعات العمل ← الخدمات ← «بانتظار التفعيل».
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  int _step = 0;
  bool _busy = false;
  String? _error;
  String? _salonCode;
  final List<String> _followUpFailures = [];

  // الخطوة 1
  final _ownerName = TextEditingController();
  final _username = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  // الخطوة 2
  final _salonName = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _about = TextEditingController();
  String _currency = 'SAR';
  String _timezone = 'Asia/Riyadh';
  bool _timezoneChosen = false;
  // الخطوة 3
  final List<_Day> _days = [for (final d in weekdaysFromSaturday) _Day(d.$1, d.$2)];
  // الخطوة 4
  final List<_NewService> _services = [];

  @override
  void dispose() {
    for (final c in [_ownerName, _username, _pass, _pass2, _salonName, _phone, _address, _about]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validate() {
    switch (_step) {
      case 0:
        if (_ownerName.text.trim().isEmpty) return 'أدخل اسمك';
        if (!RegExp(r'^[a-zA-Z0-9._-]{3,32}$').hasMatch(_username.text.trim())) {
          return 'اسم المستخدم: 3–32 حرفًا لاتينيًا أو أرقامًا';
        }
        if (_pass.text.length < 10) return 'كلمة المرور 10 أحرف على الأقل';
        if (_pass.text != _pass2.text) return 'كلمتا المرور غير متطابقتين';
      case 1:
        if (_salonName.text.trim().length < 2) return 'أدخل اسم الصالون';
      case 2:
        if (!_days.any((d) => d.open)) return 'حدّد يوم عمل واحدًا على الأقل';
      case 3:
        if (_services.isEmpty) return 'أضف خدمة واحدة على الأقل';
    }
    return null;
  }

  Future<void> _next() async {
    final err = _validate();
    setState(() => _error = err);
    if (err != null) return;
    if (_step < 3) {
      setState(() => _step++);
      return;
    }
    await _submit();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final services = ref.read(servicesProvider);
    final currency = signupCurrencies.firstWhere((c) => c.code == _currency);
    try {
      final code = await ref.read(authProvider).registerSalon(
        salonData: {
          'name': _salonName.text.trim(),
          'timezone': _timezone,
          'currency': currency.code,
          if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
          if (_address.text.trim().isNotEmpty) 'address': _address.text.trim(),
          if (_about.text.trim().isNotEmpty) 'about': _about.text.trim(),
        },
        owner: {
          'name': _ownerName.text.trim(),
          'username': _username.text.trim(),
          'password': _pass.text,
        },
      );
      // ساعات العمل والخدمات تُحفظ بجلسة المدير الجديدة (أفضل جهد).
      final cur = Currency.of(currency.code);
      // ساعات الصالون = دوام افتراضي لكل يوم (staffId: null) يظهر للزبائن.
      for (final d in _days.where((d) => d.open)) {
        try {
          await services.api.putManagerSchedule(
            weekday: serverWeekday(d.weekday),
            opensAt: wireTime(d.from),
            closesAt: wireTime(d.to),
          );
        } catch (_) {
          if (!_followUpFailures.contains('ساعات العمل')) _followUpFailures.add('ساعات العمل');
        }
      }
      for (final s in _services) {
        try {
          await services.api.createManagerService({
            'name': s.name,
            'durationMinutes': s.minutes,
            'price': cur.parse(s.priceText) ?? 0,
          });
        } catch (_) {
          if (!_followUpFailures.contains('الخدمات')) _followUpFailures.add('الخدمات');
        }
      }
      setState(() {
        _salonCode = code;
        _step = 4;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() {
    if (_step == 0 || _step == 4) {
      context.go('/login');
    } else {
      setState(() {
        _step--;
        _error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['بياناتك', 'ملف الصالون', 'ساعات العمل', 'الخدمات'];
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'سجّل صالونك',
              subtitle: _step < 4
                  ? '${digits('الخطوة ${_step + 1} من 4')} — ${titles[_step]}'
                  : 'تم إرسال طلبك',
              onBack: _busy ? null : _back,
            ),
            Expanded(child: _body()),
            if (_step < 4)
              BottomActions(children: [
                if (_error != null) SaloniBanner(tone: SaloniBannerTone.danger, body: _error),
                SaloniButton(
                  label: _step < 3 ? 'التالي' : 'إرسال للتفعيل',
                  size: SaloniButtonSize.lg,
                  block: true,
                  loading: _busy,
                  onPressed: _busy ? null : _next,
                ),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    switch (_step) {
      case 0:
        return PageBody(gap: 16, children: [
          const Muted('ستصبح مدير الصالون بهذا الحساب.'),
          SaloniTextField(label: 'اسمك', controller: _ownerName),
          SaloniTextField(
              label: 'اسم المستخدم',
              controller: _username,
              textDirection: TextDirection.ltr,
              help: HelpTexts.username),
          SaloniTextField(
              label: 'كلمة المرور',
              controller: _pass,
              type: SaloniTextFieldType.password,
              textDirection: TextDirection.ltr,
              hint: '10 أحرف على الأقل'),
          SaloniTextField(
              label: 'تأكيد كلمة المرور',
              controller: _pass2,
              type: SaloniTextFieldType.password,
              textDirection: TextDirection.ltr),
        ]);
      case 1:
        return PageBody(gap: 16, children: [
          SaloniTextField(label: 'اسم الصالون', controller: _salonName),
          SaloniTextField(
              label: 'هاتف الصالون (اختياري)',
              controller: _phone,
              type: SaloniTextFieldType.tel,
              textDirection: TextDirection.ltr,
              help: HelpTexts.salonPhone),
          SaloniTextField(label: 'العنوان (اختياري)', controller: _address),
          SaloniTextField(label: 'نبذة (اختياري)', controller: _about),
          Section(
              title: 'العملة',
              trailing: const SaloniHelpHint(HelpTexts.currency),
              children: [
                const Muted('تُعرض بها الأسعار والإيرادات. تُضبط مرة عند الإنشاء.'),
                GroupBox(children: [
                  for (var i = 0; i < signupCurrencies.length; i++)
                    _ChoiceRow(
                      key: Key('currency-${signupCurrencies[i].code}'),
                      leading: signupCurrencies[i].symbol,
                      label: signupCurrencies[i].nameAr,
                      selected: _currency == signupCurrencies[i].code,
                      first: i == 0,
                      onTap: () => setState(() {
                        _currency = signupCurrencies[i].code;
                        if (!_timezoneChosen) {
                          _timezone = signupCurrencies[i].defaultTimezone ?? _timezone;
                        }
                      }),
                    ),
                ]),
              ]),
          Section(
              title: 'بلد الصالون (التوقيت)',
              trailing: const SaloniHelpHint(HelpTexts.region),
              children: [
                const Muted('تُعرض كل المواعيد بتوقيت الصالون.'),
                GroupBox(children: [
                  for (var i = 0; i < signupRegions.length; i++)
                    _ChoiceRow(
                      key: Key('region-${signupRegions[i].$1}'),
                      label: signupRegions[i].$2,
                      selected: _timezone == signupRegions[i].$1,
                      first: i == 0,
                      onTap: () => setState(() {
                        _timezone = signupRegions[i].$1;
                        _timezoneChosen = true;
                      }),
                    ),
                ]),
              ]),
        ]);
      case 2:
        return PageBody(gap: 10, children: [
          const SaloniLabelWithHelp(label: 'ساعات الصالون', help: HelpTexts.salonHours),
          const Muted('كما تظهر للزبائن. دوام كل حلاق يُضبط لاحقًا من «الدوام».'),
          for (final d in _days) _DayRow(day: d, onChanged: () => setState(() {})),
        ]);
      case 3:
        final cur = Currency.of(_currency);
        return PageBody(gap: 10, children: [
          const Muted('الخدمات التي يحجزها الزبائن، بمدتها الأساسية وسعرها.'),
          for (final s in _services)
            Row(
              children: [
                Expanded(
                  child: ServiceChip(
                    name: s.name,
                    minutes: s.minutes,
                    price: cur.amount(cur.parse(s.priceText) ?? 0),
                    currency: cur.symbol,
                    selected: true,
                  ),
                ),
                IconButton(
                  tooltip: 'حذف',
                  onPressed: () => setState(() => _services.remove(s)),
                  icon: SaloniIcon(SaloniIconName.x, color: context.saloniColors.inkMuted),
                ),
              ],
            ),
          SaloniButton(
            label: 'إضافة خدمة',
            icon: SaloniIconName.plus,
            variant: SaloniButtonVariant.ghost,
            block: true,
            onPressed: _addService,
          ),
        ]);
      default:
        return _Pending(
          code: _salonCode ?? '',
          failures: _followUpFailures,
          onContinue: () {
            ref.read(authProvider).enterAfterSignup();
            context.go('/m/salon');
          },
        );
    }
  }

  Future<void> _addService() async {
    final name = TextEditingController();
    final minutes = TextEditingController(text: '30');
    final price = TextEditingController();
    final ok = await showSaloniSheet<bool>(context, (ctx) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SectionTitle('خدمة جديدة'),
          const SizedBox(height: 16),
          SaloniTextField(label: 'اسم الخدمة', controller: name),
          const SizedBox(height: 12),
          SaloniTextField(
              label: 'المدة الأساسية (دقيقة)',
              controller: minutes,
              type: SaloniTextFieldType.number,
              textDirection: TextDirection.ltr,
              help: HelpTexts.baseDuration),
          const SizedBox(height: 12),
          SaloniTextField(
              label: 'السعر',
              controller: price,
              type: SaloniTextFieldType.number,
              textDirection: TextDirection.ltr,
              prefix: Currency.of(_currency).symbol),
          const SizedBox(height: 20),
          SaloniButton(label: 'إضافة', block: true, onPressed: () => Navigator.of(ctx).pop(true)),
        ],
      );
    });
    final m = parseIntInput(minutes.text);
    if (ok == true && name.text.trim().isNotEmpty && m != null && m > 0) {
      setState(() => _services.add(_NewService(name.text.trim(), m, price.text)));
    }
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.first = false,
    this.leading,
  });
  final String label;

  /// علامة بصرية قبل الاسم — رمز العملة (مثل ₪)، لا علم دولة (ق41).
  final String? leading;
  final bool selected;
  final VoidCallback onTap;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.primarySoft : c.surfaceRaised,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: SaloniSizes.controlMd),
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: BorderDirectional(top: first ? BorderSide.none : BorderSide(color: c.line)),
            ),
            child: Row(children: [
              if (leading != null) ...[
                Container(
                  width: 40,
                  height: 32,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: c.surfaceSunken,
                    borderRadius: SaloniRadius.smAll,
                    border: Border.all(color: c.line),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(leading!,
                        maxLines: 1,
                        style: SaloniTextStyles.bodyStrong.copyWith(color: c.ink)),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(child: Text(label, style: SaloniTextStyles.body.copyWith(color: c.ink))),
              if (selected) SaloniIcon(SaloniIconName.check, color: c.primary, size: 20),
            ]),
          ),
        ),
      ),
    );
  }
}

/// صف يوم: مفتوح/مغلق + من/إلى.
class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.onChanged});
  final _Day day;
  final VoidCallback onChanged;

  Future<void> _pick(BuildContext context, bool from) async {
    final m = from ? day.from : day.to;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
    );
    if (t == null) return;
    if (from) {
      day.from = t.hour * 60 + t.minute;
    } else {
      day.to = t.hour * 60 + t.minute;
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return SurfaceCard(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(day.name, style: SaloniTextStyles.bodyStrong.copyWith(color: c.ink)),
          ),
          Switch(
            value: day.open,
            onChanged: (v) {
              day.open = v;
              onChanged();
            },
          ),
          const SizedBox(width: 4),
          Expanded(
            child: day.open
                ? Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 4,
                    children: [
                      SaloniButton(
                        label: displayWireTime(wireTime(day.from)),
                        size: SaloniButtonSize.sm,
                        variant: SaloniButtonVariant.secondary,
                        onPressed: () => _pick(context, true),
                      ),
                      SaloniButton(
                        label: displayWireTime(wireTime(day.to)),
                        size: SaloniButtonSize.sm,
                        variant: SaloniButtonVariant.secondary,
                        onPressed: () => _pick(context, false),
                      ),
                    ],
                  )
                : Text('مغلق',
                    textAlign: TextAlign.end,
                    style: SaloniTextStyles.body.copyWith(color: c.inkMuted)),
          ),
        ],
      ),
    );
  }
}

/// «صالونك بانتظار التفعيل» (S-Signup).
class _Pending extends StatelessWidget {
  const _Pending({required this.code, required this.failures, required this.onContinue});
  final String code;
  final List<String> failures;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const EmptyState(
          icon: SaloniIconName.hourglassMedium,
          title: 'صالونك بانتظار التفعيل',
          body: 'أرسلنا بياناتك إلى فريق صالوني. بعد التفعيل يظهر صالونك للزبائن، وتصلك رسالة هنا.',
        ),
        Container(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            border: Border.all(color: c.line),
            borderRadius: SaloniRadius.mdAll,
          ),
          child: Row(
            children: [
              Expanded(child: Text('رمز صالونك', style: SaloniTextStyles.body.copyWith(color: c.inkMuted))),
              Directionality(
                textDirection: TextDirection.ltr,
                child: SelectableText(code, style: SaloniTextStyles.code.copyWith(color: c.ink)),
              ),
            ],
          ),
        ),
        if (failures.isNotEmpty) ...[
          const SizedBox(height: 10),
          SaloniBanner(
            tone: SaloniBannerTone.warning,
            title: 'لم نتمكن من حفظ: ${failures.join('، ')}',
            body: 'أكملها من ملف الصالون.',
          ),
        ],
        const SizedBox(height: 10),
        SaloniButton(
          label: 'أكمل ملف الصالون',
          variant: SaloniButtonVariant.secondary,
          block: true,
          onPressed: onContinue,
        ),
      ],
    );
  }
}

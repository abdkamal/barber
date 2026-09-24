import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:saloni_ui/saloni_ui.dart';

import '../../core/format.dart';
import '../../state/app_services.dart';
import '../barber/more_screen.dart';
import '../common/ui.dart';
import 'manager_common.dart';

class _SettingDef {
  const _SettingDef(this.key, this.label, this.fallback, this.format, {this.max = 1440, this.min = 0});
  final String key;
  final String label;
  final int fallback;
  final String Function(int) format;
  final int max;
  final int min;
}

String _mins(int v) => v == 120
    ? 'ساعتان'
    : v == 2
        ? 'دقيقتان'
        : digits('$v د');

String _plain(int v) => digits('$v');
String _pct(int v) => digits('$v%');
String _immediate(int v) => v == 0 ? 'فورًا' : digits('$v د');

/// الإعدادات وقيمها الافتراضية (design.md §11) — بمفاتيح السيرفر.
const _bookingSettings = [
  _SettingDef('maxActiveBookingsPerCustomer', 'الحجوزات النشطة لكل زبون', 1, _plain, min: 1, max: 10),
  _SettingDef('bookingOpensBeforeMinutes', 'فتح الحجز قبل الافتتاح', 60, _mins),
  _SettingDef('etaChangeNotifyMinutes', 'هامش التنبيه الإلزامي', 30, _mins, min: 1, max: 240),
  _SettingDef('maxDisconnectWindowMinutes', 'نافذة الانقطاع القصوى', 120, _mins),
  _SettingDef('offerHoldMinutes', 'مدة حجز العرض', 2, _mins, min: 1, max: 60),
  _SettingDef('overrunAlertPercent', 'تنبيه تجاوز المدة', 100, _pct, min: 50, max: 500),
  _SettingDef('gapMarginMinMinutes', 'هامش ملء الفراغ (أدنى)', 10, _mins, max: 240),
  _SettingDef('gapMarginPercent', 'هامش ملء الفراغ (نسبة)', 25, _pct, max: 400),
  _SettingDef('barberNotConnectedAlertMinutes', 'تنبيه عدم اتصال الحلاق بعد بدء دوامه', 0,
      _immediate, max: 240),
];

/// إعدادات المدير (M-Settings) + الإدارة + QR الصالون + تفضيلات التطبيق.
class ManagerSettingsScreen extends ConsumerStatefulWidget {
  const ManagerSettingsScreen({super.key});

  @override
  ConsumerState<ManagerSettingsScreen> createState() => _ManagerSettingsScreenState();
}

class _ManagerSettingsScreenState extends ConsumerState<ManagerSettingsScreen> {
  Map<String, dynamic>? _settings;
  List<Map<String, dynamic>> _walkInOnly = const [];
  Map<String, String> _staffNames = const {};
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(servicesProvider).api;
    try {
      final s = await api.getManagerSettings();
      if (mounted) setState(() => _settings = s);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    try {
      final staff = listOf(await api.getManagerStaff());
      final b = listOf(await api.getManagerBreaks());
      if (mounted) {
        setState(() {
          _staffNames = {for (final x in staff) str(x, ['id']): str(x, ['name'])};
          _walkInOnly = b.where((x) => str(x, ['type', 'kind']) == 'walk_in_only').toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _put(Map<String, dynamic> body) async {
    try {
      final s = await ref.read(servicesProvider).api.updateManagerSettings(body);
      if (mounted) setState(() => _settings = s);
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    }
  }

  Future<void> _edit(_SettingDef d) async {
    final current = intOf(_settings, [d.key]) ?? d.fallback;
    final v = await promptText(
      context,
      title: d.label,
      label: 'القيمة',
      initial: '$current',
      type: SaloniTextFieldType.number,
      direction: TextDirection.ltr,
      hint: digits('من ${d.min} إلى ${d.max}'),
    );
    if (v == null) return;
    final n = parseIntInput(v);
    if (n == null || n < d.min || n > d.max) {
      if (mounted) toast(context, 'قيمة غير صالحة');
      return;
    }
    await _put({d.key: n});
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(prefsProvider);
    final auth = ref.watch(authProvider);
    final c = context.saloniColors;
    final s = _settings;
    final code = auth.salon?.code ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(title: 'الإعدادات', subtitle: 'تسري على الصالون كله'),
        Expanded(
          child: PageBody(onRefresh: _load, children: [
            if (_error != null && s == null) SaloniBanner(tone: SaloniBannerTone.warning, body: errorText(_error!)),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: c.line,
                border: Border.all(color: c.line),
                borderRadius: SaloniRadius.lgAll,
              ),
              child: Column(children: [
                SettingSwitch(
                  label: 'اشتراط اعتماد الحسابات',
                  description: 'لا يحجز الزبون الجديد حتى تعتمد حسابه',
                  checked: s?['requireAccountApproval'] == true,
                  onChanged: s == null ? null : (v) => _put({'requireAccountApproval': v}),
                ),
                const SizedBox(height: 1),
                SettingSwitch(
                  label: 'الأرقام العربية المشرقية',
                  description: 'عرض ٠١٢٣ بدل 0123 على هذا الجهاز',
                  checked: prefs.easternDigits,
                  onChanged: prefs.setEasternDigits,
                ),
              ]),
            ),
            Section(title: 'الحجز', children: [
              GroupBox(children: [
                for (var i = 0; i < _bookingSettings.length; i++)
                  ValueRow(
                    first: i == 0,
                    label: _bookingSettings[i].label,
                    value: s == null
                        ? '—'
                        : _bookingSettings[i].format(
                            intOf(s, [_bookingSettings[i].key]) ?? _bookingSettings[i].fallback),
                    onTap: s == null ? null : () => _edit(_bookingSettings[i]),
                  ),
              ]),
            ]),
            Section(title: 'فترات الحاضرين فقط', children: [
              const SaloniBanner(
                tone: SaloniBannerTone.info,
                body: 'لا تُقبل حجوزات التطبيق في هذه الفترات، ويخدم فيها الحلاق زبائن حاضرين.',
              ),
              for (final b in _walkInOnly)
                SurfaceCard(
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 14),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        '${_staffNames[str(b, ['staffId'])] ?? 'حلاق'} · ${breakWhen(b)}',
                        style: SaloniTextStyles.body.copyWith(color: c.ink),
                      ),
                    ),
                    Text(breakTimes(b), style: SaloniTextStyles.bodyStrong.copyWith(color: c.ink)),
                  ]),
                ),
              SaloniButton(
                label: 'إدارة الفترات والدوام',
                variant: SaloniButtonVariant.ghost,
                block: true,
                onPressed: () => context.push('/m/schedules'),
              ),
            ]),
            Section(title: 'الإدارة', children: [
              GroupBox(children: [
                ValueRow(first: true, label: 'الطاقم والصلاحيات', value: 'فتح', onTap: () => context.push('/m/staff')),
                ValueRow(label: 'الزبائن', value: 'فتح', onTap: () => context.push('/m/customers')),
                ValueRow(label: 'الدوام والاستراحات والإجازات', value: 'فتح', onTap: () => context.push('/m/schedules')),
                ValueRow(label: 'إجراءات مستردة للمراجعة', value: 'فتح', onTap: () => context.push('/m/recovered')),
                ValueRow(label: 'طابوري (إن كنت تحلق أيضًا)', value: 'فتح', onTap: () => context.go('/b/queue')),
              ]),
            ]),
            if (code.isNotEmpty)
              Section(title: 'QR الصالون', children: [
                const Muted('يمسحه الزبون من تطبيق «صالوني» ليصل إلى صفحة صالونك.'),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(color: Colors.white, borderRadius: SaloniRadius.lgAll),
                    child: QrImageView(data: code, size: 180, backgroundColor: Colors.white),
                  ),
                ),
                Center(
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: SelectableText(code, style: SaloniTextStyles.code.copyWith(color: c.ink)),
                  ),
                ),
              ]),
            const AppPreferencesSection(showDigits: false),
          ]),
        ),
      ],
    );
  }
}

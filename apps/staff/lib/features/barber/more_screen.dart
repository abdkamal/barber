import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saloni_ui/saloni_ui.dart';

import '../../core/format.dart';
import '../../state/app_services.dart';
import '../common/first_run.dart';
import '../common/ui.dart';

/// المزيد (الحلاق): المظهر، الأرقام، الجولة التعريفية، الخروج.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'المزيد',
          subtitle: [
            if (auth.accountName != null) auth.accountName!,
            if (auth.salon?.name != null) auth.salon!.name!,
          ].join(' · '),
        ),
        Expanded(
          child: PageBody(children: [
            if (auth.isManager)
              SaloniButton(
                label: 'لوحة المدير',
                icon: SaloniIconName.chartBar,
                variant: SaloniButtonVariant.secondary,
                block: true,
                onPressed: () => context.go('/m/queues'),
              ),
            const AppPreferencesSection(),
          ]),
        ),
      ],
    );
  }
}

/// تفضيلات التطبيق والحساب — مشتركة بين «المزيد» وإعدادات المدير.
class AppPreferencesSection extends ConsumerWidget {
  const AppPreferencesSection({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final repoPending = ref.exists(barberRepoProvider) ? ref.read(barberRepoProvider).pending : 0;
    final ok = await confirmDialog(
      context,
      title: 'تسجيل الخروج',
      body: repoPending > 0
          ? 'لديك ${digits('$repoPending')} إجراء لم يُزامن بعد وسيُفقد عند الخروج، لأن بيانات '
              'الطابور تُمسح من الجهاز. انتظر عودة الاتصال إن أمكن.'
          : 'تُمسح بيانات الطابور المحفوظة على هذا الجهاز.',
      confirm: 'خروج',
      danger: true,
    );
    if (ok) await signOut(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsProvider);
    final auth = ref.watch(authProvider);
    final c = context.saloniColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(title: 'المظهر', children: [
          SaloniSegmentedControl(
            label: 'المظهر',
            value: prefs.themeMode == ThemeMode.light ? 'light' : 'dark',
            options: const [
              SaloniSegmentedOption(value: 'dark', label: 'داكن'),
              SaloniSegmentedOption(value: 'light', label: 'فاتح'),
            ],
            onChanged: (v) => prefs.setThemeMode(v == 'light' ? ThemeMode.light : ThemeMode.dark),
          ),
          ClipRRect(
            borderRadius: SaloniRadius.lgAll,
            child: SettingSwitch(
              label: 'الأرقام العربية المشرقية',
              description: 'عرض ٠١٢٣ بدل 0123 على هذا الجهاز',
              checked: prefs.easternDigits,
              onChanged: prefs.setEasternDigits,
            ),
          ),
        ]),
        const SizedBox(height: 20),
        Section(title: 'الحساب', children: [
          GroupBox(children: [
            ValueRow(first: true, label: 'رمز الصالون', value: auth.salon?.code ?? '—'),
            ValueRow(label: 'الصلاحية', value: auth.isManager ? 'مدير' : 'حلاق'),
            ValueRow(
              label: 'الجولة التعريفية',
              value: 'عرض',
              onTap: () => showOnboarding(context, auth.isManager ? 'manager' : 'barber'),
            ),
          ]),
          SaloniButton(
            key: const Key('logout'),
            label: 'تسجيل الخروج',
            icon: SaloniIconName.signOut,
            variant: SaloniButtonVariant.secondary,
            block: true,
            onPressed: () => _logout(context, ref),
          ),
          Text('صالوني — احجز دوري · الطاقم',
              textAlign: TextAlign.center,
              style: SaloniTextStyles.caption.copyWith(color: c.inkSubtle)),
        ]),
      ],
    );
  }
}

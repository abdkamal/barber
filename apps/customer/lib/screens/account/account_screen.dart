import 'package:flutter/material.dart';
import 'package:saloni_ui/saloni_ui.dart' as ui;

import '../../models/salon_session.dart';

/// شاشة الحساب — تسجيل الخروج، المظهر، الصالونات المحفوظة (ق7).
class AccountScreen extends StatelessWidget {
  const AccountScreen({
    super.key,
    required this.activeCode,
    required this.savedSalons,
    required this.isDark,
    required this.onToggleTheme,
    required this.onSwitchSalon,
    required this.onAddSalon,
    required this.onRemoveSalon,
    required this.onLogout,
  });

  final String? activeCode;
  final List<SalonSession> savedSalons;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final ValueChanged<String> onSwitchSalon;
  final VoidCallback onAddSalon;
  final ValueChanged<String> onRemoveSalon;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حسابي')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('المظهر', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: ui.SettingSwitch(
                label: 'الوضع الفاتح',
                description: 'الوضع الداكن هو الافتراضي',
                checked: !isDark,
                onChanged: (_) => onToggleTheme(),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('صالوناتي', style: Theme.of(context).textTheme.titleMedium),
                TextButton.icon(
                  onPressed: onAddSalon,
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة صالون'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final s in savedSalons)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                  child: ListTile(
                    leading: ui.SaloniAvatar(name: s.name, size: 36),
                    title: Text(s.name),
                    subtitle: Text(s.code),
                    trailing: s.code == activeCode
                        ? const Icon(Icons.check_circle)
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => onRemoveSalon(s.code),
                          ),
                    onTap: s.code == activeCode ? null : () => onSwitchSalon(s.code),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            ui.SaloniButton(
              label: 'تسجيل الخروج',
              variant: ui.SaloniButtonVariant.danger,
              icon: ui.SaloniIconName.signOut,
              block: true,
              onPressed: onLogout,
            ),
          ],
        ),
      ),
    );
  }
}

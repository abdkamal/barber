import 'package:flutter/material.dart';
import 'package:saloni_ui/saloni_ui.dart' as ui;

/// حالة «بانتظار الاعتماد» — إعداد المدير الذي يشترط موافقة الحسابات (ق6).
class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key, required this.onRetry, required this.onLogout});

  final Future<void> Function() onRetry;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ui.EmptyState(
            icon: ui.SaloniIconName.hourglassMedium,
            title: 'حسابك بانتظار اعتماد الصالون',
            body: 'ستتمكن من الحجز فور اعتماد حسابك، وسنرسل لك تنبيهًا.',
            action: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ui.SaloniButton(label: 'تحديث', onPressed: () => onRetry()),
                const SizedBox(height: 8),
                TextButton(onPressed: onLogout, child: const Text('تسجيل الخروج')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

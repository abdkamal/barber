import 'package:flutter/material.dart';
import 'package:saloni_ui/saloni_ui.dart';

import '../services/notification_service.dart';

/// تحذير عربي واضح عند تعذّر الإشعارات أو عدم توفر خدمات Google (ق31).
class NotificationWarningBanner extends StatelessWidget {
  const NotificationWarningBanner({super.key, required this.readiness});

  final NotificationReadiness? readiness;

  @override
  Widget build(BuildContext context) {
    final r = readiness;
    if (r == null || r.isFullyReady) return const SizedBox.shrink();

    final String message;
    if (!r.hasPlayServices) {
      message =
          'خدمات Google Play غير متوفرة على هذا الجهاز — لن تصلك إشعارات فورية (الاستدعاء، تغيّر الوقت). راجع شاشة المتابعة يدويًا.';
    } else if (!r.notificationsAllowed) {
      message =
          'إذن الإشعارات غير مفعّل — لن تصلك تنبيهات عند اقتراب دورك. يمكنك تفعيله من إعدادات النظام.';
    } else {
      message = 'تعذّر تفعيل الإشعارات على هذا الجهاز حاليًا.';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SaloniBanner(tone: SaloniBannerTone.warning, title: 'تنبيه بشأن الإشعارات', body: message),
    );
  }
}

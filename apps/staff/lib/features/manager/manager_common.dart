import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saloni_api/saloni_api.dart' as sa;
import 'package:saloni_ui/saloni_ui.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../state/app_services.dart';
import '../common/ui.dart';

/// شارة حالة يوم الحلاق (design.md §4).
class DayStateBadge extends StatelessWidget {
  const DayStateBadge({super.key, required this.state});
  final sa.BarberDayState? state;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (state) {
      sa.BarberDayState.connected => ('متصل', SaloniTone.success),
      sa.BarberDayState.disconnected => ('منقطع', SaloniTone.warning),
      sa.BarberDayState.absentToday => ('غائب اليوم', SaloniTone.danger),
      sa.BarberDayState.notConnectedYet => ('لم يتصل بعد', SaloniTone.neutral),
      null => ('—', SaloniTone.neutral),
    };
    return StatusBadge(status: BookingStatus.waiting, small: true, label: label, tone: tone);
  }
}

/// تنبيه «صالونك بانتظار التفعيل» (ق37).
class PendingActivationBanner extends ConsumerWidget {
  const PendingActivationBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salon = ref.watch(authProvider).salon;
    if (salon == null || !salon.pendingActivation) return const SizedBox.shrink();
    return const SaloniBanner(
      tone: SaloniBannerTone.info,
      title: 'صالونك بانتظار التفعيل',
      body:
          'لا يظهر للزبائن قبل تفعيله من فريق صالوني. أكمل بياناته وخدماته في الأثناء — '
          'يمكنك إضافة الشعار والصور بعد التفعيل.',
    );
  }
}

/// حوار إدخال نصي/رقمي بسيط بأسلوب نظام التصميم.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  SaloniTextFieldType type = SaloniTextFieldType.text,
  TextDirection? direction,
  String? hint,
  String confirm = 'حفظ',
}) async {
  final ctrl = TextEditingController(text: initial);
  final ok = await showSaloniSheet<bool>(context, (ctx) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionTitle(title),
        const SizedBox(height: 16),
        SaloniTextField(label: label, controller: ctrl, type: type, textDirection: direction, hint: hint),
        const SizedBox(height: 20),
        SaloniButton(label: confirm, block: true, onPressed: () => Navigator.of(ctx).pop(true)),
      ],
    );
  });
  return ok == true ? ctrl.text : null;
}

/// عرض رمز لمرة واحدة (إعادة التعيين) بخط الرموز.
Future<void> showOneTimeCode(BuildContext context, String who, String code, {String? expires}) {
  return showSaloniSheet<void>(context, (ctx) {
    final c = ctx.saloniColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionTitle('رمز إعادة التعيين — $who'),
        const SizedBox(height: 8),
        const Muted('سلّمه لصاحبه ليعيّن كلمة مرور جديدة. صالح لمرة واحدة خلال 24 ساعة، '
            'وتُلغى كل جلساته. لا يُعرض مرة أخرى.'),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surfaceSunken,
            borderRadius: SaloniRadius.mdAll,
            border: Border.all(color: c.line),
          ),
          alignment: Alignment.center,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SelectableText(code, style: SaloniTextStyles.code.copyWith(color: c.ink, fontSize: 22)),
          ),
        ),
        if (expires != null) ...[const SizedBox(height: 8), Muted(expires, center: true)],
        const SizedBox(height: 20),
        SaloniButton(label: 'تم', block: true, onPressed: () => Navigator.of(ctx).pop()),
      ],
    );
  });
}

/// رابط صورة مخزنة: `salonId/file` ← `{base}/v1/media/{code}/{file}`.
String mediaUrl(String path, String salonCode) {
  if (path.startsWith('http')) return path;
  var base = AppConfig.apiBaseUrl;
  if (base.endsWith('/')) base = base.substring(0, base.length - 1);
  final i = path.lastIndexOf('/');
  final file = i >= 0 ? path.substring(i + 1) : path;
  return '$base/v1/media/$salonCode/$file';
}

/// «يوميًا» أو التاريخ لاستراحة/فترة من `GET /manager/breaks`.
String breakWhen(Map<String, dynamic> b) =>
    b['recurring'] == true || str(b, ['workDate']).isEmpty ? 'يوميًا' : digits(str(b, ['workDate']));

/// «4:00 م – 6:00 م».
String breakTimes(Map<String, dynamic> b) {
  if (str(b, ['startTime']).isNotEmpty) {
    return '${displayWireTime(str(b, ['startTime']))} – ${displayWireTime(str(b, ['endTime']))}';
  }
  final s = DateTime.tryParse(str(b, ['startsAt']));
  final e = DateTime.tryParse(str(b, ['endsAt']));
  if (s == null || e == null) return '—';
  return '${timeAr(s)} – ${timeAr(e)}';
}

String breakTypeAr(String t) => switch (t) {
      'rest' => 'راحة',
      'prayer' => 'صلاة',
      'emergency' => 'طارئة',
      'walk_in_only' => 'حاضرون فقط',
      _ => t,
    };

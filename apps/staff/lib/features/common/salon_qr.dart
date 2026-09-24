import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:saloni_ui/saloni_ui.dart';

import '../../state/app_services.dart';
import 'ui.dart';

/// محتوى رمز QR للصالون: رمز الصالون نفسه — تطبيق الزبون يأخذ قيمة المسح
/// كما هي ويعاملها رمزَ صالون (`apps/customer`: `salon_entry_screen.dart`)،
/// وهو ما تعرضه إعدادات المدير أيضًا.
String salonQrData(String code) => code.trim();

/// يعرض رمز QR للصالون فورًا في ورقة سفلية، مع الرمز نصًا وزر نسخه.
Future<void> showSalonQr(BuildContext context, {required String code, String? salonName}) {
  return showSaloniSheet<void>(context, (ctx) => SalonQrSheet(code: code, salonName: salonName));
}

class SalonQrSheet extends StatelessWidget {
  const SalonQrSheet({super.key, required this.code, this.salonName});
  final String code;
  final String? salonName;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    final data = salonQrData(code);
    return Column(
      key: const Key('salon-qr-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('رمز الصالون', style: SaloniTextStyles.title2.copyWith(color: c.ink)),
        if (salonName != null && salonName!.isNotEmpty)
          Text(salonName!, style: SaloniTextStyles.caption.copyWith(color: c.inkMuted)),
        const SizedBox(height: 16),
        if (data.isEmpty)
          const Muted('رمز الصالون غير متاح الآن — أعد الدخول ثم حاول مجددًا.')
        else ...[
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(color: Colors.white, borderRadius: SaloniRadius.lgAll),
              child: QrImageView(
                key: const Key('salon-qr-image'),
                data: data,
                size: 220,
                backgroundColor: Colors.white,
                semanticsLabel: 'رمز QR للصالون $data',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(
                data,
                key: const Key('salon-qr-code'),
                style: SaloniTextStyles.code.copyWith(color: c.ink, fontSize: 22),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'يمسحه الزبون من تطبيق «صالوني» أو يكتب الرمز، ليصل إلى صفحة الصالون ويحجز.',
            textAlign: TextAlign.center,
            style: SaloniTextStyles.caption.copyWith(color: c.inkMuted),
          ),
          const SizedBox(height: 16),
          SaloniButton(
            key: const Key('salon-qr-copy'),
            label: 'نسخ الرمز',
            variant: SaloniButtonVariant.secondary,
            block: true,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: data));
              if (context.mounted) toast(context, 'نُسخ رمز الصالون $data');
            },
          ),
        ],
        const SizedBox(height: 10),
        SaloniButton(
          label: 'إغلاق',
          variant: SaloniButtonVariant.ghost,
          block: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// زر QR في الشريط العلوي للتطبيق (للمدير والحلاق).
class SalonQrButton extends ConsumerWidget {
  const SalonQrButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final c = context.saloniColors;
    return Semantics(
      button: true,
      label: 'رمز QR للصالون',
      child: Material(
        color: c.surfaceRaised,
        shape: RoundedRectangleBorder(borderRadius: SaloniRadius.mdAll, side: BorderSide(color: c.line)),
        child: InkWell(
          key: const Key('salon-qr'),
          borderRadius: SaloniRadius.mdAll,
          onTap: () => showSalonQr(context, code: auth.salon?.code ?? '', salonName: auth.salon?.name),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(child: SaloniIcon(SaloniIconName.qrCode, color: c.ink)),
          ),
        ),
      ),
    );
  }
}

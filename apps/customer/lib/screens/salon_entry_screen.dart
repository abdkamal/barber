import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:saloni_ui/saloni_ui.dart' as ui;

/// شاشة البداية: إدخال رمز الصالون أو مسح QR (ق7).
class SalonEntryScreen extends StatefulWidget {
  const SalonEntryScreen({super.key, required this.onSubmit, this.onGoRegisterSalon});

  final ValueChanged<String> onSubmit;
  final VoidCallback? onGoRegisterSalon;

  @override
  State<SalonEntryScreen> createState() => _SalonEntryScreenState();
}

class _SalonEntryScreenState extends State<SalonEntryScreen> {
  final _controller = TextEditingController();

  void _submit() {
    final code = _controller.text.trim();
    if (code.isEmpty) return;
    widget.onSubmit(code);
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScanScreen()),
    );
    if (code != null && code.isNotEmpty) {
      _controller.text = code;
      widget.onSubmit(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 64, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'صالوني',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                'احجز دوري — وقتك محفوظ وأنت في مكانك.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const Spacer(),
              ui.SaloniTextField(
                label: 'رمز الصالون',
                controller: _controller,
                textDirection: TextDirection.ltr,
                hint: 'تجده على لوحة الصالون أو اطلبه من الحلاق',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              ui.SaloniButton(
                label: 'متابعة',
                size: ui.SaloniButtonSize.lg,
                block: true,
                onPressed: _controller.text.trim().isEmpty ? null : _submit,
              ),
              const SizedBox(height: 10),
              ui.SaloniButton(
                label: 'مسح رمز QR',
                variant: ui.SaloniButtonVariant.secondary,
                icon: ui.SaloniIconName.qrCode,
                block: true,
                onPressed: _scan,
              ),
              const Spacer(),
              Center(
                child: TextButton(
                  onPressed: widget.onGoRegisterSalon,
                  child: const Text('صاحب صالون؟ سجّل صالونك'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrScanScreen extends StatelessWidget {
  const _QrScanScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مسح رمز الصالون')),
      body: MobileScanner(
        onDetect: (capture) {
          final barcodes = capture.barcodes;
          if (barcodes.isEmpty) return;
          final value = barcodes.first.rawValue;
          if (value != null && value.isNotEmpty) {
            Navigator.of(context).pop(value);
          }
        },
      ),
    );
  }
}

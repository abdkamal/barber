import 'package:flutter/material.dart';
import 'package:saloni_ui/saloni_ui.dart' as ui;

/// تسجيل الدخول (ق17: «الدخول تلقائيًا»).
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.salonName,
    required this.onSubmit,
    this.onGoRegister,
  });

  final String salonName;
  final Future<void> Function({
    required String phone,
    required String password,
    required bool rememberMe,
  }) onSubmit;
  final VoidCallback? onGoRegister;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _rememberMe = true;
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        phone: '+966${_phone.text.trim()}',
        password: _password.text,
        rememberMe: _rememberMe,
      );
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل الدخول')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('في ${widget.salonName}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              ui.SaloniTextField(
                label: 'رقم الهاتف',
                controller: _phone,
                type: ui.SaloniTextFieldType.tel,
                prefix: '+966',
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(height: 16),
              ui.SaloniTextField(
                label: 'كلمة المرور',
                controller: _password,
                type: ui.SaloniTextFieldType.password,
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: ui.SettingSwitch(
                  label: 'الدخول تلقائيًا',
                  description: 'تذكّر حسابي على هذا الجهاز',
                  checked: _rememberMe,
                  onChanged: (v) => setState(() => _rememberMe = v),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                ui.SaloniBanner(tone: ui.SaloniBannerTone.danger, body: _error),
              ],
              const SizedBox(height: 24),
              ui.SaloniButton(
                label: 'تسجيل الدخول',
                size: ui.SaloniButtonSize.lg,
                block: true,
                loading: _loading,
                onPressed: _loading ? null : _submit,
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: widget.onGoRegister,
                  child: const Text('حساب جديد؟ إنشاء حساب'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

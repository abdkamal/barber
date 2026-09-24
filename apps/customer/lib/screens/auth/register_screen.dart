import 'package:flutter/material.dart';
import 'package:saloni_ui/saloni_ui.dart' as ui;

/// إنشاء حساب — ق17 (كلمة مرور إلزامية، «الدخول تلقائيًا» اختياري).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.salonName,
    required this.onSubmit,
    this.onGoLogin,
  });

  final String salonName;

  /// يرمي [Exception] برسالة عربية عند الفشل (تُعرض في الشاشة).
  final Future<void> Function({
    required String name,
    required String phone,
    required String password,
    required bool rememberMe,
  }) onSubmit;

  final VoidCallback? onGoLogin;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _rememberMe = true;
  bool _loading = false;
  String? _error;

  String? get _validationError {
    if (_name.text.trim().isEmpty) return 'الاسم مطلوب';
    if (_phone.text.trim().length < 8) return 'رقم الهاتف غير صحيح';
    if (_password.text.length < 8) return 'كلمة المرور 8 أحرف على الأقل';
    return null;
  }

  Future<void> _submit() async {
    final err = _validationError;
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        name: _name.text.trim(),
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
      appBar: AppBar(
        title: const Text('إنشاء حساب'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('في ${widget.salonName}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              ui.SaloniTextField(label: 'الاسم', controller: _name),
              const SizedBox(height: 16),
              ui.SaloniTextField(
                label: 'رقم الهاتف',
                controller: _phone,
                type: ui.SaloniTextFieldType.tel,
                prefix: '+966',
                textDirection: TextDirection.ltr,
                hint: 'يستخدمه الصالون للتواصل معك فقط',
              ),
              const SizedBox(height: 16),
              ui.SaloniTextField(
                label: 'كلمة المرور',
                controller: _password,
                type: ui.SaloniTextFieldType.password,
                hint: '8 أحرف على الأقل',
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
              const SizedBox(height: 16),
              const ui.SaloniBanner(
                tone: ui.SaloniBannerTone.info,
                title: 'يراجع الصالون الحسابات الجديدة',
                body: 'ستتمكن من الحجز بعد اعتماد حسابك إن كان ذلك مفعّلًا. سنرسل لك تنبيهًا.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                ui.SaloniBanner(tone: ui.SaloniBannerTone.danger, body: _error),
              ],
              const SizedBox(height: 24),
              ui.SaloniButton(
                label: 'إنشاء الحساب',
                size: ui.SaloniButtonSize.lg,
                block: true,
                loading: _loading,
                onPressed: _loading ? null : _submit,
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: widget.onGoLogin,
                  child: const Text('لديك حساب؟ تسجيل الدخول'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

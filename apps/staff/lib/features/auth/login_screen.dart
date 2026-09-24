import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saloni_ui/saloni_ui.dart';

import '../../state/app_services.dart';
import '../common/ui.dart';

/// دخول الطاقم: رمز الصالون + اسم المستخدم + كلمة المرور + «الدخول تلقائيًا»
/// (ق17، ق18، design.md §7). على نسق شاشة البداية في النموذج (Main).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  late final TextEditingController _code;
  late final TextEditingController _user;
  final _pass = TextEditingController();
  bool _remember = true;
  bool _busy = false;
  String? _error;
  String? _codeError;
  String? _userError;
  String? _passError;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(prefsProvider);
    _code = TextEditingController(text: prefs.lastSalonCode ?? '');
    _user = TextEditingController(text: prefs.lastUsername ?? '');
  }

  @override
  void dispose() {
    _code.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _codeError = _code.text.trim().isEmpty ? 'أدخل رمز الصالون' : null;
      _userError = _user.text.trim().isEmpty ? 'أدخل اسم المستخدم' : null;
      _passError = _pass.text.isEmpty ? 'أدخل كلمة المرور' : null;
      _error = null;
    });
    if (_codeError != null || _userError != null || _passError != null) return;
    setState(() => _busy = true);
    try {
      await ref.read(authProvider).login(
            salonCode: _code.text,
            username: _user.text,
            password: _pass.text,
            rememberMe: _remember,
          );
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    final notice = ref.watch(authProvider).forcedSignOutNotice;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 48, 16, 24),
          children: [
            Text('صالوني',
                textAlign: TextAlign.center,
                style: SaloniTextStyles.display.copyWith(color: c.primary)),
            Text('الطاقم — الحلاق والمدير',
                textAlign: TextAlign.center,
                style: SaloniTextStyles.body.copyWith(color: c.inkMuted)),
            const SizedBox(height: 40),
            if (notice != null) ...[
              SaloniBanner(tone: SaloniBannerTone.info, body: notice),
              const SizedBox(height: 16),
            ],
            SaloniTextField(
              label: 'رمز الصالون',
              controller: _code,
              textDirection: TextDirection.ltr,
              placeholder: 'RAHA-27',
              error: _codeError,
              hint: 'تجده عند مدير الصالون',
            ),
            const SizedBox(height: 16),
            SaloniTextField(
              label: 'اسم المستخدم',
              controller: _user,
              textDirection: TextDirection.ltr,
              error: _userError,
            ),
            const SizedBox(height: 16),
            SaloniTextField(
              label: 'كلمة المرور',
              controller: _pass,
              type: SaloniTextFieldType.password,
              textDirection: TextDirection.ltr,
              error: _passError,
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: SaloniRadius.lgAll,
              child: SettingSwitch(
                label: 'الدخول تلقائيًا',
                description: 'يحفظ الجلسة على هذا الجهاز الخاص بك',
                checked: _remember,
                onChanged: (v) => setState(() => _remember = v),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              SaloniBanner(tone: SaloniBannerTone.danger, body: _error),
            ],
            const SizedBox(height: 24),
            SaloniButton(
              label: 'دخول',
              size: SaloniButtonSize.lg,
              block: true,
              loading: _busy,
              onPressed: _busy ? null : _submit,
            ),
            const SizedBox(height: 10),
            SaloniButton(
              label: 'لديّ رمز إعادة تعيين',
              variant: SaloniButtonVariant.ghost,
              block: true,
              onPressed: () => context.go('/reset'),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('صاحب صالون؟ ', style: SaloniTextStyles.caption.copyWith(color: c.inkSubtle)),
                InkWell(
                  onTap: () => context.go('/signup'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('سجّل صالونك',
                        style: SaloniTextStyles.caption.copyWith(color: c.primary)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

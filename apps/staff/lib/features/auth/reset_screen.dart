import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saloni_ui/saloni_ui.dart';

import '../../state/app_services.dart';
import '../common/ui.dart';

/// تعيين كلمة مرور جديدة برمز لمرة واحدة من المدير (ق31، design.md §7).
class ResetScreen extends ConsumerStatefulWidget {
  const ResetScreen({super.key});

  @override
  ConsumerState<ResetScreen> createState() => _ResetScreenState();
}

class _ResetScreenState extends ConsumerState<ResetScreen> {
  late final TextEditingController _code;
  late final TextEditingController _user;
  final _reset = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(prefsProvider);
    _code = TextEditingController(text: prefs.lastSalonCode ?? '');
    _user = TextEditingController(text: prefs.lastUsername ?? '');
  }

  @override
  void dispose() {
    for (final c in [_code, _user, _reset, _pass, _pass2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    String? err;
    if (_code.text.trim().isEmpty || _user.text.trim().isEmpty || _reset.text.trim().isEmpty) {
      err = 'أكمل كل الحقول';
    } else if (_pass.text.length < 10) {
      err = 'كلمة مرور الطاقم 10 أحرف على الأقل';
    } else if (_pass.text != _pass2.text) {
      err = 'كلمتا المرور غير متطابقتين';
    }
    setState(() => _error = err);
    if (err != null) return;
    setState(() => _busy = true);
    try {
      await ref.read(servicesProvider).api.requestPasswordReset(
            salonCode: _code.text.trim().toUpperCase(),
            identifier: _user.text.trim(),
            code: _reset.text.trim(),
            newPassword: _pass.text,
          );
      if (mounted) setState(() => _done = true);
    } catch (e, st) {
      if (mounted) setState(() => _error = errorText(e, st));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'كلمة مرور جديدة',
              subtitle: 'برمز لمرة واحدة من مدير الصالون',
              onBack: () => context.go('/login'),
            ),
            Expanded(
              child: _done
                  ? ListView(children: [
                      EmptyState(
                        icon: SaloniIconName.checkCircle,
                        title: 'تم تعيين كلمة المرور',
                        body: 'سجّل الدخول الآن بكلمة المرور الجديدة.',
                        action: SaloniButton(label: 'إلى الدخول', onPressed: () => context.go('/login')),
                      ),
                    ])
                  : PageBody(gap: 16, children: [
                      SaloniTextField(label: 'رمز الصالون', controller: _code, textDirection: TextDirection.ltr),
                      SaloniTextField(label: 'اسم المستخدم', controller: _user, textDirection: TextDirection.ltr),
                      SaloniTextField(
                          label: 'رمز إعادة التعيين',
                          controller: _reset,
                          textDirection: TextDirection.ltr,
                          hint: 'صالح 24 ساعة، لمرة واحدة'),
                      SaloniTextField(
                          label: 'كلمة المرور الجديدة',
                          controller: _pass,
                          type: SaloniTextFieldType.password,
                          textDirection: TextDirection.ltr,
                          hint: '10 أحرف على الأقل'),
                      SaloniTextField(
                          label: 'تأكيد كلمة المرور',
                          controller: _pass2,
                          type: SaloniTextFieldType.password,
                          textDirection: TextDirection.ltr),
                      if (_error != null) SaloniBanner(tone: SaloniBannerTone.danger, body: _error),
                    ]),
            ),
            if (!_done)
              BottomActions(children: [
                SaloniButton(
                  label: 'حفظ كلمة المرور',
                  size: SaloniButtonSize.lg,
                  block: true,
                  loading: _busy,
                  onPressed: _busy ? null : _submit,
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

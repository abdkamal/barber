import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saloni_api/saloni_api.dart' as sa;
import 'package:saloni_ui/saloni_ui.dart';

import '../../core/format.dart';
import '../../state/app_services.dart';
import '../common/ui.dart';

/// «N إجراءات» بصيغة عربية سليمة.
String actionsAr(int n) => switch (n) {
      1 => 'إجراء واحد',
      2 => 'إجراءان',
      _ when n >= 3 && n <= 10 => digits('$n إجراءات'),
      _ => digits('$n إجراءً'),
    };

/// ق40: «سلّم الجهاز للمدير» — الجهاز يحمل إجراءات لم تُرفع لحساب موقوف (أو
/// لحساب غير الذي يحاول الدخول). لا يُمسح شيء إلا بعد رفع المدير أو «مسح دون
/// رفع» بتأكيد صريح. المدير يدخل هنا بجلسة لا تُحفظ على الجهاز.
class HoldScreen extends ConsumerStatefulWidget {
  const HoldScreen({super.key});

  @override
  ConsumerState<HoldScreen> createState() => _HoldScreenState();
}

class _HoldScreenState extends ConsumerState<HoldScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _userError;
  String? _passError;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _recover() async {
    setState(() {
      _userError = _user.text.trim().isEmpty ? 'أدخل اسم مستخدم المدير' : null;
      _passError = _pass.text.isEmpty ? 'أدخل كلمة المرور' : null;
      _error = null;
    });
    if (_userError != null || _passError != null) return;
    setState(() => _busy = true);
    try {
      await ref.read(authProvider).recoverWithManager(username: _user.text, password: _pass.text);
      _pass.clear();
    } catch (e, st) {
      if (mounted) setState(() => _error = errorText(e, st));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discard(DeviceHold h) async {
    final ok = await confirmDialog(
      context,
      title: 'مسح دون رفع؟',
      body: 'سيُحذف ${actionsAr(h.pending)} من هذا الجهاز نهائيًا ولن تصل إلى السيرفر '
          '(لن تُسجَّل خدمات أو دفعات تمت دون اتصال). لا يمكن التراجع.',
      confirm: 'مسح نهائيًا',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(authProvider).discardHeld();
    } catch (e, st) {
      if (mounted) setState(() => _error = errorText(e, st));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final h = auth.hold;
    if (h == null) return const Scaffold(body: SizedBox.shrink());
    final report = auth.recoveryReport;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: switch (h.reason) {
                HoldReason.accountSuspended => 'الحساب موقوف',
                HoldReason.salonSuspended => 'الصالون موقوف',
                HoldReason.otherAccount => 'إجراءات حساب آخر',
              },
              subtitle: digits('${h.username} · ${h.salonCode}'),
            ),
            Expanded(
              child: PageBody(
                children: report != null ? _result(context, h, report) : _pending(context, h),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _pending(BuildContext context, DeviceHold h) {
    final what = actionsAr(h.pending);
    return [
      SaloniBanner(
        tone: SaloniBannerTone.warning,
        title: '$what لم تُرفع بعد',
        body: switch (h.reason) {
          HoldReason.accountSuspended =>
            'أُوقف حساب «${h.username}»، وبقي على هذا الجهاز $what محفوظة مشفّرة. '
                'سلّم الجهاز للمدير لرفعها — يُقبل منها ما تم قبل وقت الإيقاف فقط.',
          HoldReason.salonSuspended =>
            'الصالون موقوف حاليًا، وبقي على هذا الجهاز $what محفوظة مشفّرة. '
                'ستُرفع عند إعادة تفعيله بدخول صاحب الحساب أو المدير.',
          HoldReason.otherAccount =>
            'على هذا الجهاز $what محفوظة مشفّرة لحساب «${h.username}». '
                'لا يمكن الدخول بحساب آخر قبل رفعها: ليدخل صاحب الحساب لإكمال المزامنة، '
                'أو سلّم الجهاز للمدير.',
        },
      ),
      Section(title: 'دخول المدير', children: [
        const Muted('يدخل المدير هنا بحسابه ليرفع الإجراءات؛ لا تُحفظ جلسته على هذا الجهاز.'),
        SaloniTextField(
          label: 'اسم مستخدم المدير',
          controller: _user,
          textDirection: TextDirection.ltr,
          error: _userError,
        ),
        SaloniTextField(
          label: 'كلمة المرور',
          controller: _pass,
          type: SaloniTextFieldType.password,
          textDirection: TextDirection.ltr,
          error: _passError,
        ),
        if (_error != null) SaloniBanner(tone: SaloniBannerTone.danger, body: _error),
        SaloniButton(
          label: 'دخول المدير ورفع الإجراءات',
          size: SaloniButtonSize.lg,
          block: true,
          loading: _busy,
          onPressed: _busy ? null : _recover,
        ),
      ]),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SaloniButton(
            label: 'رجوع لتسجيل الدخول',
            variant: SaloniButtonVariant.ghost,
            block: true,
            onPressed: _busy ? null : () => ref.read(authProvider).finishHold(),
          ),
          const SizedBox(height: 10),
          SaloniButton(
            label: 'مسح دون رفع',
            icon: SaloniIconName.warning,
            variant: SaloniButtonVariant.danger,
            block: true,
            onPressed: _busy ? null : () => _discard(h),
          ),
        ],
      ),
    ];
  }

  List<Widget> _result(BuildContext context, DeviceHold h, sa.RecoveryReport r) {
    final s = r.summary;
    final wiped = h.pending == 0;
    return [
      SaloniBanner(
        tone: s.rejected == 0 ? SaloniBannerTone.success : SaloniBannerTone.warning,
        title: 'اكتمل الرفع',
        body: wiped
            ? 'مُسحت بيانات حساب «${h.username}» من هذا الجهاز. '
                'الإجراءات المقبولة معلّمة للمراجعة في «إجراءات مستردة للمراجعة».'
            : 'بقي ${actionsAr(h.pending)} لم يصل ردّها — أعد المحاولة.',
      ),
      GroupBox(children: [
        ValueRow(first: true, label: 'قُبلت', value: digits('${s.accepted}')),
        ValueRow(label: 'رُفضت لوقوعها بعد الإيقاف', value: digits('${s.rejectedAfterSuspension}')),
        if (s.rejectedUncertainTime > 0)
          ValueRow(label: 'لم تُطبّق لعدم التأكد من وقتها', value: digits('${s.rejectedUncertainTime}')),
        if (s.rejectedInvalid > 0)
          ValueRow(label: 'رُفضت لعدم صلاحيتها', value: digits('${s.rejectedInvalid}')),
      ]),
      // ق40 (مراجعة F1): أُعيد تشغيل الجهاز دون اتصال فوقتها تقريبي — لا تُطبّق، وتُحفظ للمراجعة.
      if (s.rejectedUncertainTime > 0)
        const Muted('أُعيد تشغيل الجهاز وهو دون اتصال، فلا يُعرف أوقعت هذه الإجراءات قبل الإيقاف أم بعده. '
            'لم تُطبّق، وحُفظت في «إجراءات مستردة للمراجعة» لتسجّلها يدويًا إن كانت قد حدثت فعلًا.'),
      if (r.suspendedAt != null) Muted('وقت الإيقاف: ${weekdayAr(r.suspendedAt!)} ${timeAr(r.suspendedAt!)}'),
      SaloniButton(
        label: 'تم',
        size: SaloniButtonSize.lg,
        block: true,
        onPressed: () => wiped
            ? ref.read(authProvider).finishHold()
            : ref.read(authProvider).dismissRecoveryReport(),
      ),
    ];
  }
}

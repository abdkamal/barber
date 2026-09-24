import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saloni_ui/saloni_ui.dart';

import '../../core/format.dart';
import '../../core/help_texts.dart';
import '../../state/app_services.dart';
import '../common/shells.dart';
import '../common/ui.dart';
import 'manager_common.dart';

/// الطاقم والصلاحيات (ق18، ق25، design.md §7).
class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});

  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  Key _reloadKey = UniqueKey();

  void _reload() => setState(() => _reloadKey = UniqueKey());

  Future<void> _add() async {
    final name = TextEditingController();
    final user = TextEditingController();
    final pass = TextEditingController();
    var role = 'barber';
    String? error;
    final api = ref.read(servicesProvider).api;
    await showSaloniSheet<void>(context, (ctx) {
      return StatefulBuilder(builder: (ctx, setState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SectionTitle('إضافة عضو للطاقم'),
            const SizedBox(height: 14),
            SaloniTextField(label: 'الاسم', controller: name),
            const SizedBox(height: 12),
            SaloniTextField(
                label: 'اسم المستخدم',
                controller: user,
                textDirection: TextDirection.ltr,
                help: HelpTexts.username),
            const SizedBox(height: 12),
            SaloniTextField(
              label: 'كلمة مرور مؤقتة',
              controller: pass,
              type: SaloniTextFieldType.password,
              textDirection: TextDirection.ltr,
              help: HelpTexts.tempPassword,
            ),
            const SizedBox(height: 12),
            const SaloniLabelWithHelp(label: 'الصلاحية', help: HelpTexts.role),
            const SizedBox(height: 4),
            SaloniSegmentedControl(
              label: 'الصلاحية',
              value: role,
              options: const [
                SaloniSegmentedOption(value: 'barber', label: 'حلاق'),
                SaloniSegmentedOption(value: 'manager', label: 'مدير'),
              ],
              onChanged: (v) => setState(() => role = v),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              SaloniBanner(tone: SaloniBannerTone.danger, body: error),
            ],
            const SizedBox(height: 20),
            SaloniButton(
              label: 'إضافة',
              size: SaloniButtonSize.lg,
              block: true,
              onPressed: () async {
                if (pass.text.length < 10) {
                  setState(() => error = 'كلمة مرور الطاقم 10 أحرف على الأقل');
                  return;
                }
                try {
                  await api.createManagerStaff({
                    'name': name.text.trim(),
                    'username': user.text.trim(),
                    'password': pass.text,
                    'role': role,
                  });
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } catch (e) {
                  setState(() => error = errorText(e));
                }
              },
            ),
          ],
        );
      });
    });
    _reload();
  }

  Future<void> _edit(Map<String, dynamic> s) async {
    final api = ref.read(servicesProvider).api;
    var role = str(s, ['role'], 'barber');
    var active = s['active'] != false;
    final callAhead = TextEditingController(text: '${intOf(s, ['call_ahead_minutes', 'callAheadMinutes']) ?? 20}');
    final id = str(s, ['id']);
    final action = await showSaloniSheet<String>(context, (ctx) {
      return StatefulBuilder(builder: (ctx, setState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SectionTitle(str(s, ['name'], '—')),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(str(s, ['username']),
                  textAlign: TextAlign.end,
                  style: SaloniTextStyles.code.copyWith(color: ctx.saloniColors.inkMuted)),
            ),
            const SizedBox(height: 14),
            const SaloniLabelWithHelp(label: 'الصلاحية', help: HelpTexts.role),
            const SizedBox(height: 4),
            SaloniSegmentedControl(
              label: 'الصلاحية',
              value: role,
              options: const [
                SaloniSegmentedOption(value: 'barber', label: 'حلاق'),
                SaloniSegmentedOption(value: 'manager', label: 'مدير'),
              ],
              onChanged: (v) => setState(() => role = v),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: SaloniRadius.lgAll,
              child: SettingSwitch(
                label: 'الحساب نشط',
                description: HelpTexts.staffActive.summary,
                help: HelpTexts.staffActive,
                checked: active,
                onChanged: (v) => setState(() => active = v),
              ),
            ),
            const SizedBox(height: 12),
            SaloniTextField(
              label: 'مدة التنبيه قبل الدور (دقيقة)',
              controller: callAhead,
              type: SaloniTextFieldType.number,
              textDirection: TextDirection.ltr,
              help: HelpTexts.callAheadMinutes,
            ),
            const SizedBox(height: 20),
            SaloniButton(label: 'حفظ', size: SaloniButtonSize.lg, block: true, onPressed: () => Navigator.of(ctx).pop('save')),
            if (str(s, ['role']) == 'barber') ...[
              const SizedBox(height: 10),
              SaloniButton(
                label: 'إصدار رمز إعادة تعيين',
                icon: SaloniIconName.lockSimple,
                variant: SaloniButtonVariant.secondary,
                block: true,
                onPressed: () => Navigator.of(ctx).pop('reset'),
              ),
            ],
          ],
        );
      });
    });
    if (action == null || !mounted) return;
    try {
      if (action == 'reset') {
        final r = await api.resetStaffCode(id);
        if (mounted) {
          await showOneTimeCode(context, str(s, ['name']), str(r, ['code', 'resetCode'], '—'),
              expires: str(r, ['expiresAt']).isEmpty
                  ? null
                  : 'ينتهي ${timeAr(DateTime.parse(str(r, ['expiresAt'])))}');
        }
      } else {
        await api.updateManagerStaff(id, {
          if (role != str(s, ['role'])) 'role': role,
          if (active != (s['active'] != false)) 'active': active,
          if (parseIntInput(callAhead.text) != null) 'callAheadMinutes': parseIntInput(callAhead.text),
        });
        _reload();
      }
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.read(servicesProvider).api;
    return DetailScaffold(
      title: 'الطاقم',
      subtitle: 'الحلاقون والمديرون وصلاحياتهم',
      body: AsyncView<List<Map<String, dynamic>>>(
        key: _reloadKey,
        load: () async => listOf(await api.getManagerStaff()),
        builder: (context, list, reload) => PageBody(onRefresh: reload, gap: 10, children: [
          for (final s in list)
            SurfaceCard(
              onTap: () => _edit(s),
              child: Row(children: [
                SaloniAvatar(
                  name: str(s, ['name'], '؟'),
                  tone: str(s, ['role']) == 'manager' ? SaloniAvatarTone.steel : SaloniAvatarTone.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(str(s, ['name'], '—'),
                        style: SaloniTextStyles.bodyStrong.copyWith(color: context.saloniColors.ink)),
                    Muted('${str(s, ['role']) == 'manager' ? 'مدير' : 'حلاق'} · ${str(s, ['username'])}'),
                  ]),
                ),
                if (s['active'] == false)
                  const StatusBadge(status: BookingStatus.cancelled, small: true, label: 'موقوف'),
              ]),
            ),
          SaloniButton(
            label: 'إضافة عضو',
            icon: SaloniIconName.userPlus,
            variant: SaloniButtonVariant.ghost,
            block: true,
            onPressed: _add,
          ),
        ]),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saloni_ui/saloni_ui.dart';
import 'package:saloni_api/saloni_api.dart' as sa;

import '../../core/help_texts.dart';
import '../../state/app_services.dart';
import '../common/shells.dart';
import '../common/ui.dart';
import 'manager_common.dart';

/// الزبائن: اعتماد / إيقاف / رمز إعادة تعيين / ربط سجل حاضر / نزاع رقم
/// (ق6، ق20، design.md §10).
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _filter = 'all';
  Key _reloadKey = UniqueKey();

  void _reload() => setState(() => _reloadKey = UniqueKey());

  bool _isWalkIn(Map<String, dynamic> c) =>
      c['is_walk_in'] == true || c['isWalkIn'] == true || c['walkIn'] == true;

  (String, SaloniTone) _status(Map<String, dynamic> c) {
    if (_isWalkIn(c)) return ('حاضر', SaloniTone.neutral);
    return switch (str(c, ['status'])) {
      'pending' => ('بانتظار الاعتماد', SaloniTone.warning),
      'suspended' => ('موقوف', SaloniTone.danger),
      _ => ('نشط', SaloniTone.success),
    };
  }

  Future<void> _act(Map<String, dynamic> c, List<Map<String, dynamic>> all) async {
    final api = ref.read(servicesProvider).api;
    final id = str(c, ['id']);
    // ق20: الربط اليدوي بسجل حاضر يحمل نفس رقم الهاتف ولم يُربط بعد.
    final linked = {for (final x in all) str(x, ['linked_walk_in_id', 'linkedWalkInId'])};
    final walkIns = all
        .where((x) =>
            _isWalkIn(x) &&
            str(x, ['phone']) == str(c, ['phone']) &&
            !linked.contains(str(x, ['id'])))
        .toList();
    final status = str(c, ['status']);
    // H2: سجل حاضر مربوط فعليًا أو مقترح (بانتظار اعتماد الحساب).
    final hasLinkedWalkIn = str(c, ['linked_walk_in_id', 'linkedWalkInId']).isNotEmpty ||
        str(c, ['proposed_walk_in_id', 'proposedWalkInId']).isNotEmpty;
    final action = await showSaloniSheet<String>(context, (ctx) {
      final col = ctx.saloniColors;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SectionTitle(str(c, ['name'], 'زبون'), trailing: const SaloniHelpHint(HelpTexts.customerActions)),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(str(c, ['phone']),
                textAlign: TextAlign.end, style: SaloniTextStyles.body.copyWith(color: col.inkMuted)),
          ),
          if (intOf(c, ['no_show_count', 'noShowCount']) != null && intOf(c, ['no_show_count', 'noShowCount'])! > 0)
            Muted('لم يحضر ${intOf(c, ['no_show_count', 'noShowCount'])} مرة'),
          const SizedBox(height: 16),
          if (status == 'pending')
            SaloniButton(
              label: 'اعتماد الحساب',
              icon: SaloniIconName.checkCircle,
              size: SaloniButtonSize.lg,
              block: true,
              onPressed: () => Navigator.of(ctx).pop('approve'),
            ),
          if (!_isWalkIn(c)) ...[
            const SizedBox(height: 10),
            SaloniButton(
              label: 'إصدار رمز إعادة تعيين',
              icon: SaloniIconName.lockSimple,
              variant: SaloniButtonVariant.secondary,
              block: true,
              onPressed: () => Navigator.of(ctx).pop('reset'),
            ),
            if (walkIns.isNotEmpty) ...[
              const SizedBox(height: 10),
              SaloniButton(
                label: 'ربط سجل زبون حاضر',
                icon: SaloniIconName.userPlus,
                variant: SaloniButtonVariant.secondary,
                block: true,
                onPressed: () => Navigator.of(ctx).pop('link'),
              ),
            ],
            if (hasLinkedWalkIn) ...[
              const SizedBox(height: 10),
              SaloniButton(
                label: 'فك ربط سجل الحاضر',
                icon: SaloniIconName.x,
                variant: SaloniButtonVariant.secondary,
                block: true,
                onPressed: () => Navigator.of(ctx).pop('unlink'),
              ),
            ],
            const SizedBox(height: 10),
            SaloniButton(
              label: 'تعديل رقم الهاتف',
              icon: SaloniIconName.phone,
              variant: SaloniButtonVariant.secondary,
              block: true,
              onPressed: () => Navigator.of(ctx).pop('reassign-phone'),
            ),
          ],
          if (status != 'suspended' && !_isWalkIn(c)) ...[
            const SizedBox(height: 10),
            SaloniButton(
              label: 'إيقاف الحساب',
              variant: SaloniButtonVariant.danger,
              block: true,
              onPressed: () => Navigator.of(ctx).pop('suspend'),
            ),
          ],
          if (status == 'suspended' && !_isWalkIn(c)) ...[
            const SizedBox(height: 10),
            SaloniButton(
              label: 'الإفراج عن الرقم',
              icon: SaloniIconName.xCircle,
              variant: SaloniButtonVariant.danger,
              block: true,
              onPressed: () => Navigator.of(ctx).pop('release-phone'),
            ),
          ],
        ],
      );
    });
    if (action == null || !mounted) return;
    try {
      switch (action) {
        case 'approve':
          await api.approveCustomer(id);
          if (mounted) toast(context, 'اعتُمد الحساب');
        case 'suspend':
          final ok = await confirmDialog(context,
              title: 'إيقاف الحساب',
              body: 'لن يستطيع ${str(c, ['name'])} الحجز حتى تعيد تفعيله.',
              confirm: 'إيقاف',
              danger: true);
          if (!ok) return;
          await api.suspendCustomer(id);
        case 'reset':
          final r = await api.resetCustomerCode(id);
          if (mounted) await showOneTimeCode(context, str(c, ['name']), str(r, ['code', 'resetCode'], '—'));
        case 'link':
          if (!mounted) return;
          final target = await showSaloniSheet<String>(context, (ctx) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SectionTitle('اختر سجل الحاضر'),
                const SizedBox(height: 6),
                const Muted('يُنقل تاريخ زياراته إلى هذا الحساب (ق20). تُسجَّل العملية.'),
                const SizedBox(height: 12),
                GroupBox(children: [
                  for (var i = 0; i < walkIns.length; i++)
                    ValueRow(
                      first: i == 0,
                      label: str(walkIns[i], ['name'], 'حاضر'),
                      value: str(walkIns[i], ['phone']),
                      onTap: () => Navigator.of(ctx).pop(str(walkIns[i], ['id'])),
                    ),
                ]),
              ],
            );
          });
          if (target == null) return;
          await api.linkWalkInRecord(id, target);
          if (mounted) toast(context, 'رُبط السجل');
        case 'unlink':
          final ok = await confirmDialog(context,
              title: 'فك ربط سجل الحاضر',
              body: 'يفصل سجل الزيارات السابقة عن حساب ${str(c, ['name'])} (H2).',
              confirm: 'فك الربط',
              danger: true);
          if (!ok) return;
          await api.unlinkWalkInRecord(id);
          if (mounted) toast(context, 'فُكّ الربط');
        case 'reassign-phone':
          if (!mounted) return;
          final controller = TextEditingController();
          final newPhone = await showSaloniSheet<String>(context, (ctx) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SectionTitle('تعديل رقم الهاتف'),
                const SizedBox(height: 6),
                const Muted('تُلغى جلسات الحساب الحالية وربط سجله عند تغيير الرقم (H2).'),
                const SizedBox(height: 12),
                SaloniTextField(
                  label: 'الرقم الجديد',
                  controller: controller,
                  textDirection: TextDirection.ltr,
                ),
                const SizedBox(height: 14),
                SaloniButton(
                  label: 'حفظ',
                  size: SaloniButtonSize.lg,
                  block: true,
                  onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                ),
              ],
            );
          });
          if (newPhone == null || newPhone.isEmpty) return;
          await api.updateCustomerPhone(id, newPhone);
          if (mounted) toast(context, 'تحديث رقم الهاتف');
        case 'release-phone':
          final ok = await confirmDialog(context,
              title: 'الإفراج عن الرقم',
              body:
                  'يبقى حساب ${str(c, ['name'])} موقوفًا، ويصبح رقمه متاحًا ليسجّل به صاحبه الحقيقي من جديد (H2).',
              confirm: 'الإفراج',
              danger: true);
          if (!ok) return;
          await api.releaseCustomerPhone(id);
          if (mounted) toast(context, 'أُفرج عن الرقم');
      }
      _reload();
    } catch (e, st) {
      if (mounted) toast(context, errorText(e, st));
    }
  }

  /// نزاع رقم (ق20): عدة سجلات حاضرين بنفس رقم حساب — يختار المدير السجل الصحيح.
  Future<void> _resolve(sa.PhoneDispute d) async {
    final walkIns = d.walkIns;
    final accountId = d.accountId ?? '';
    if (accountId.isEmpty) {
      toast(context, 'لا يوجد حساب تطبيق بهذا الرقم بعد — يُحل النزاع عند تسجيله.');
      return;
    }
    final chosen = await showSaloniSheet<String>(context, (ctx) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SectionTitle('نزاع على الرقم ${d.phone}'),
          const SizedBox(height: 6),
          const Muted('اختر سجل الحاضر الذي يخص صاحب الحساب؛ يُربط به ويُسجَّل ذلك.'),
          const SizedBox(height: 12),
          GroupBox(children: [
            for (var i = 0; i < walkIns.length; i++)
              ValueRow(
                first: i == 0,
                label: walkIns[i].name.isEmpty ? 'حاضر' : walkIns[i].name,
                value: 'ربط',
                onTap: () => Navigator.of(ctx).pop(walkIns[i].id),
              ),
          ]),
        ],
      );
    });
    if (chosen == null) return;
    try {
      await ref.read(servicesProvider).api.resolvePhoneDispute(accountId: accountId, walkInId: chosen);
      _reload();
    } catch (e, st) {
      if (mounted) toast(context, errorText(e, st));
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.read(servicesProvider).api;
    return DetailScaffold(
      title: 'الزبائن',
      subtitle: 'الاعتماد والإيقاف وربط السجلات',
      body: AsyncView<(List<Map<String, dynamic>>, List<sa.PhoneDispute>)>(
        key: _reloadKey,
        load: () async {
          final customers = listOf(await api.getManagerCustomers(), ['customers', 'items']);
          var disputes = const <sa.PhoneDispute>[];
          try {
            disputes = await api.getPhoneDisputes();
          } on sa.ApiError catch (_) {}
          return (customers, disputes);
        },
        builder: (context, data, reload) {
          final (all, disputes) = data;
          final shown = all.where((c) {
            switch (_filter) {
              case 'pending':
                return str(c, ['status']) == 'pending';
              case 'suspended':
                return str(c, ['status']) == 'suspended';
              case 'walkin':
                return _isWalkIn(c);
              default:
                return true;
            }
          }).toList();
          return PageBody(onRefresh: reload, gap: 10, children: [
            for (final d in disputes)
              SaloniBanner(
                tone: SaloniBannerTone.warning,
                title: 'نزاع على الرقم ${d.phone}',
                body: 'أكثر من سجل زبون حاضر بهذا الرقم — اختر السجل الذي يخص صاحب الحساب.',
                action: SaloniButton(
                  label: 'حلّ النزاع',
                  size: SaloniButtonSize.sm,
                  variant: SaloniButtonVariant.secondary,
                  onPressed: () => _resolve(d),
                ),
              ),
            SaloniSegmentedControl(
              label: 'تصفية',
              value: _filter,
              options: const [
                SaloniSegmentedOption(value: 'all', label: 'الكل'),
                SaloniSegmentedOption(value: 'pending', label: 'للاعتماد'),
                SaloniSegmentedOption(value: 'suspended', label: 'موقوف'),
                SaloniSegmentedOption(value: 'walkin', label: 'حاضرون'),
              ],
              onChanged: (v) => setState(() => _filter = v),
            ),
            if (shown.isEmpty) const EmptyState(icon: SaloniIconName.usersThree, title: 'لا زبائن هنا'),
            for (final c in shown)
              SurfaceCard(
                onTap: () => _act(c, all),
                child: Row(children: [
                  SaloniAvatar(name: str(c, ['name'], '؟')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(str(c, ['name'], 'زبون'),
                          style: SaloniTextStyles.bodyStrong.copyWith(color: context.saloniColors.ink)),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(str(c, ['phone']),
                            style: SaloniTextStyles.caption.copyWith(color: context.saloniColors.inkMuted)),
                      ),
                    ]),
                  ),
                  Builder(builder: (_) {
                    final (label, tone) = _status(c);
                    return StatusBadge(status: BookingStatus.waiting, small: true, label: label, tone: tone);
                  }),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:saloni_ui/saloni_ui.dart';

import '../../core/format.dart';
import '../../state/app_services.dart';
import '../common/ui.dart';

/// محرر عنصر الكتالوج (خدمة/منتج) — ق37. يعيد `true` إن حُفظ أو حُذف.
Future<bool> editCatalogItem(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic>? item,
  List<Map<String, dynamic>> services,
  Currency cur,
) async {
  final result = await showSaloniSheet<bool>(
    context,
    (ctx) => _CatalogEditor(item: item, services: services, cur: cur),
  );
  return result == true;
}

class _CatalogEditor extends ConsumerStatefulWidget {
  const _CatalogEditor({required this.item, required this.services, required this.cur});
  final Map<String, dynamic>? item;
  final List<Map<String, dynamic>> services;
  final Currency cur;

  @override
  ConsumerState<_CatalogEditor> createState() => _CatalogEditorState();
}

class _CatalogEditorState extends ConsumerState<_CatalogEditor> {
  late String _kind = str(widget.item, ['kind', 'type'], 'service');
  late final _name = TextEditingController(text: str(widget.item, ['name']));
  late final _desc = TextEditingController(text: str(widget.item, ['description']));
  late final _features = TextEditingController(
    text: widget.item?['features'] is List ? (widget.item!['features'] as List).join('، ') : '',
  );
  late final _price = TextEditingController(
    text: intOf(widget.item, ['price', 'priceCents']) == null
        ? ''
        : widget.cur.amount(intOf(widget.item, ['price', 'priceCents'])!).replaceAll(',', ''),
  );
  late bool _visible = widget.item?['visible'] != false;
  late String? _serviceId = str(widget.item, ['serviceId']).isEmpty ? null : str(widget.item, ['serviceId']);
  ({List<int> bytes, String name, String type})? _photo;
  bool _busy = false;
  String? _error;

  Future<void> _pickPhoto() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    setState(() => _photo = (
          bytes: bytes,
          name: f.name,
          type: f.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg',
        ));
  }

  Future<void> _save() async {
    final price = widget.cur.parse(_price.text);
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'أدخل الاسم');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final isNew = str(widget.item, ['id']).isEmpty;
    final body = <String, dynamic>{
      if (isNew) 'kind': _kind,
      'name': _name.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'features': [
        for (final f in _features.text.split(RegExp('[،,]')))
          if (f.trim().isNotEmpty) f.trim(),
      ],
      'price': price,
      'visible': _visible,
      if (isNew && _kind == 'service' && _serviceId != null) 'serviceId': _serviceId,
    };
    try {
      final services = ref.read(servicesProvider);
      var id = str(widget.item, ['id']);
      if (id.isEmpty) {
        final created = await services.api.createManagerCatalogItem(body);
        id = str(created, ['id']);
      } else {
        await services.api.updateManagerCatalogItem(id, body);
      }
      final photo = _photo;
      if (photo != null && id.isNotEmpty) {
        await services.raw.uploadCatalogPhoto(
            id, photo.bytes, photo.name, photo.type);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context,
        title: 'حذف العنصر', body: 'يُزال من صفحة «حول الصالون».', confirm: 'حذف', danger: true);
    if (!ok) return;
    try {
      await ref.read(servicesProvider).api.deleteManagerCatalogItem(str(widget.item, ['id']));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionTitle(widget.item == null ? 'إضافة خدمة أو منتج' : 'تعديل ${str(widget.item, ['name'])}'),
        const SizedBox(height: 14),
        SaloniSegmentedControl(
          label: 'النوع',
          value: _kind,
          options: const [
            SaloniSegmentedOption(value: 'service', label: 'خدمة', icon: SaloniIconName.scissors),
            SaloniSegmentedOption(value: 'product', label: 'منتج', icon: SaloniIconName.package),
          ],
          onChanged: (v) => setState(() => _kind = v),
        ),
        const SizedBox(height: 12),
        SaloniTextField(label: 'الاسم', controller: _name),
        const SizedBox(height: 12),
        SaloniTextField(label: 'الوصف', controller: _desc),
        const SizedBox(height: 12),
        SaloniTextField(label: 'المزايا', controller: _features, hint: 'افصل بينها بفاصلة: غسيل، تصفيف'),
        const SizedBox(height: 12),
        SaloniTextField(
          label: 'السعر',
          controller: _price,
          prefix: widget.cur.symbol,
          type: SaloniTextFieldType.number,
          textDirection: TextDirection.ltr,
        ),
        if (_kind == 'service' && widget.services.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('مرتبطة بالخدمة القابلة للحجز', style: SaloniTextStyles.label.copyWith(color: context.saloniColors.ink)),
          const SizedBox(height: 8),
          GroupBox(children: [
            for (var i = 0; i < widget.services.length; i++)
              ValueRow(
                first: i == 0,
                label: str(widget.services[i], ['name']),
                value: _serviceId == str(widget.services[i], ['id']) ? '✓' : '',
                onTap: () => setState(() => _serviceId = str(widget.services[i], ['id'])),
              ),
          ]),
        ],
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: SaloniRadius.lgAll,
          child: SettingSwitch(
            label: 'ظاهر للزبائن',
            checked: _visible,
            onChanged: (v) => setState(() => _visible = v),
          ),
        ),
        const SizedBox(height: 12),
        SaloniButton(
          label: _photo == null ? 'صورة العنصر' : 'تم اختيار صورة',
          icon: SaloniIconName.image,
          variant: SaloniButtonVariant.secondary,
          block: true,
          onPressed: _pickPhoto,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          SaloniBanner(tone: SaloniBannerTone.danger, body: _error),
        ],
        const SizedBox(height: 20),
        SaloniButton(label: 'حفظ', size: SaloniButtonSize.lg, block: true, loading: _busy, onPressed: _busy ? null : _save),
        if (widget.item != null) ...[
          const SizedBox(height: 10),
          SaloniButton(label: 'حذف', variant: SaloniButtonVariant.ghost, block: true, onPressed: _delete),
        ],
      ],
    );
  }
}

/// محرر الخدمة القابلة للحجز (الاسم، المدة الأساسية، السعر، نشطة؟).
Future<bool> editService(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic>? service,
  Currency cur,
) async {
  final name = TextEditingController(text: str(service, ['name']));
  final minutes = TextEditingController(
      text: '${intOf(service, ['durationMinutes', 'baseDurationMin']) ?? 30}');
  final price = TextEditingController(
    text: intOf(service, ['price', 'priceCents']) == null
        ? ''
        : cur.amount(intOf(service, ['price', 'priceCents'])!).replaceAll(',', ''),
  );
  var active = service?['active'] != false;
  final action = await showSaloniSheet<String>(context, (ctx) {
    return StatefulBuilder(builder: (ctx, setState) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SectionTitle(service == null ? 'خدمة جديدة' : 'تعديل الخدمة'),
          const SizedBox(height: 14),
          SaloniTextField(label: 'اسم الخدمة', controller: name),
          const SizedBox(height: 12),
          SaloniTextField(
              label: 'المدة الأساسية (دقيقة)',
              controller: minutes,
              type: SaloniTextFieldType.number,
              textDirection: TextDirection.ltr),
          const SizedBox(height: 12),
          SaloniTextField(
              label: 'السعر',
              controller: price,
              prefix: cur.symbol,
              type: SaloniTextFieldType.number,
              textDirection: TextDirection.ltr),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: SaloniRadius.lgAll,
            child: SettingSwitch(
              label: 'متاحة للحجز',
              checked: active,
              onChanged: (v) => setState(() => active = v),
            ),
          ),
          const SizedBox(height: 20),
          SaloniButton(label: 'حفظ', size: SaloniButtonSize.lg, block: true, onPressed: () => Navigator.of(ctx).pop('save')),
          if (service != null) ...[
            const SizedBox(height: 10),
            SaloniButton(
                label: 'حذف', variant: SaloniButtonVariant.ghost, block: true, onPressed: () => Navigator.of(ctx).pop('delete')),
          ],
        ],
      );
    });
  });
  if (action == null) return false;
  final api = ref.read(servicesProvider).api;
  try {
    if (action == 'delete') {
      await api.deleteManagerService(str(service, ['id']));
      return true;
    }
    final m = parseIntInput(minutes.text);
    if (name.text.trim().isEmpty || m == null || m <= 0) {
      if (context.mounted) toast(context, 'أدخل الاسم والمدة');
      return false;
    }
    final body = {
      'name': name.text.trim(),
      'durationMinutes': m,
      'price': cur.parse(price.text) ?? 0,
      if (service != null) 'active': active,
    };
    if (service == null) {
      final created = await api.createManagerService(body);
      if (!active) await api.updateManagerService(str(created, ['id']), {'active': false});
    } else {
      await api.updateManagerService(str(service, ['id']), body);
    }
    return true;
  } catch (e) {
    if (context.mounted) toast(context, errorText(e));
    return false;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:saloni_api/saloni_api.dart' show normalizeInternationalPhone;
import 'package:saloni_ui/saloni_ui.dart';

import '../../core/format.dart';
import '../../core/help_texts.dart';
import '../../state/app_services.dart';
import '../common/ui.dart';
import 'manager_common.dart';
import 'salon_editors.dart';

/// ملف الصالون (M-Salon؛ ق37): الشعار، البيانات، الموقع، الصور (حتى 6)،
/// الخدمات والمنتجات (الكتالوج)، والخدمات القابلة للحجز.
class SalonScreen extends ConsumerStatefulWidget {
  const SalonScreen({super.key});

  @override
  ConsumerState<SalonScreen> createState() => _SalonScreenState();
}

class _SalonScreenState extends ConsumerState<SalonScreen> {
  final _name = TextEditingController();
  final _about = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _instagram = TextEditingController();
  double? _lat;
  double? _lng;
  String? _logo;
  List<Map<String, dynamic>> _photos = const [];
  List<Map<String, dynamic>> _catalog = const [];
  List<Map<String, dynamic>> _services = const [];
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _about, _address, _phone, _whatsapp, _instagram]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(servicesProvider).api;
    try {
      final p = await api.getManagerProfile();
      _name.text = str(p, ['name']);
      _about.text = str(p, ['about']);
      _address.text = str(p, ['address']);
      final contact = p['contact'] is Map ? p['contact'] as Map : p;
      _phone.text = str(contact, ['phone']);
      _whatsapp.text = str(contact, ['whatsapp']);
      final social = p['socialLinks'] ?? contact['social'];
      if (social is List) {
        for (final l in social) {
          if (l is Map && '${l['platform']}'.toLowerCase().contains('instagram')) {
            _instagram.text = '${l['url'] ?? ''}';
          }
        }
      }
      final loc = p['location'];
      if (loc is Map) {
        _lat = (loc['lat'] as num?)?.toDouble();
        _lng = (loc['lng'] as num?)?.toDouble();
      }
      _logo = str(p, ['logo', 'logoUrl']);
      // السيرفر لا يعيد الصور في ملف المدير حاليًا؛ نبقي ما رُفع في هذه الجلسة.
      if (p['photos'] is List) _photos = listOf(p, ['photos']);
      _error = null;
    } catch (e) {
      _error = e;
    }
    try {
      _catalog = listOf(await api.getManagerCatalog());
    } catch (_) {}
    try {
      _services = listOf(await api.getManagerServices());
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String? _whatsappError;

  /// رقم واتساب دولي كامل أو فارغ (null). يعيد `false` إن كان غير صالح.
  (bool, String?) _whatsappValue() {
    final raw = _whatsapp.text.trim();
    if (raw.isEmpty) return (true, null);
    final n = normalizeInternationalPhone(raw);
    return (n != null, n);
  }

  Future<void> _save() async {
    final (waOk, wa) = _whatsappValue();
    setState(() => _whatsappError =
        waOk ? null : 'اكتب الرقم كاملًا مع رمز الدولة ويبدأ بـ + (مثل ‎+970 59 123 4567)');
    if (!waOk) return;
    if (wa != null) _whatsapp.text = wa;
    setState(() => _saving = true);
    try {
      await ref.read(servicesProvider).api.updateManagerProfile({
        'name': _name.text.trim(),
        'about': _nullIfEmpty(_about.text),
        'address': _nullIfEmpty(_address.text),
        'phone': _nullIfEmpty(_phone.text),
        'whatsapp': wa,
        'socialLinks': [
          if (_instagram.text.trim().isNotEmpty)
            {'platform': 'instagram', 'url': _instagramUrl(_instagram.text.trim())},
        ],
        if (_lat != null && _lng != null) 'location': {'lat': _lat, 'lng': _lng},
      });
      if (mounted) toast(context, 'حُفظ ملف الصالون');
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _locate() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) toast(context, 'لم يُسمح بالوصول للموقع. فعّله من إعدادات الهاتف.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
      if (mounted) toast(context, 'حُدّد موقع الصالون — اضغط «حفظ» لاعتماده');
    } catch (e) {
      if (mounted) toast(context, 'تعذّر تحديد الموقع');
    }
  }

  /// رفع صورة (الصور أو الشعار). يضغطها السيرفر ويزيل بيانات EXIF (§7).
  ///
  /// **قبل التفعيل** (`pending_activation`) يرفض السيرفر الرفع
  /// (`409 SALON_NOT_ACTIVE` — مراجعة المرحلة 6)؛ الزر معطَّل عندها أصلًا
  /// (انظر البناء أدناه) فلا يصل المستخدم لهذا الاستدعاء، لكن نُبقي الرسالة
  /// هنا احتياطًا (مثلًا إن تغيّرت حالة الصالون أثناء فتح الشاشة).
  Future<void> _upload({required bool logo}) async {
    if (!logo && _photos.length >= 6) {
      toast(context, 'الحد الأقصى 6 صور');
      return;
    }
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final name = file.name.toLowerCase();
      final type = name.endsWith('.png')
          ? 'image/png'
          : name.endsWith('.webp')
              ? 'image/webp'
              : 'image/jpeg';
      final api = ref.read(servicesProvider).api;
      if (logo) {
        final r = await api.uploadManagerLogo(bytes: bytes, filename: file.name, contentType: type);
        setState(() => _logo = str(r, ['logo', 'path']));
      } else {
        final r = await api.uploadManagerPhoto(bytes: bytes, filename: file.name, contentType: type);
        setState(() => _photos = [
              ..._photos,
              {'id': r.id, 'url': r.url ?? r.path, 'position': r.position},
            ]);
      }
      if (mounted) toast(context, 'رُفعت الصورة');
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    }
  }

  Future<void> _deletePhoto(Map<String, dynamic> p) async {
    final ok = await confirmDialog(context,
        title: 'حذف الصورة', body: 'تُحذف من صفحة «حول الصالون».', confirm: 'حذف', danger: true);
    if (!ok) return;
    try {
      await ref.read(servicesProvider).api.deleteManagerPhoto(str(p, ['id']));
      setState(() => _photos = _photos.where((x) => str(x, ['id']) != str(p, ['id'])).toList());
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    }
  }

  /// رابط `/v1/media/{code}/{file}` (أو مسار مخزَّن `salonId/file`) ← رابط كامل
  /// (يُعرض للصالونات المفعّلة فقط).
  String _url(String path) => mediaUrl(path, ref.read(authProvider).salon?.code ?? '');

  static String? _nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();

  static String _instagramUrl(String v) {
    if (v.startsWith('http')) return v;
    final handle = v.startsWith('@') ? v.substring(1) : v;
    return 'https://instagram.com/$handle';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    final auth = ref.watch(authProvider);
    final cur = auth.currency;
    // مراجعة المرحلة 6: رفع الصور والشعار يُرفض (409 SALON_NOT_ACTIVE) قبل
    // تفعيل الصالون — تُعطَّل الأزرار بدل محاولة رفع تفشل دون تفسير.
    final uploadsBlocked = auth.salon?.pendingActivation ?? false;
    final initial = _name.text.trim().isEmpty ? 'ص' : _name.text.trim().characters.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(title: 'ملف الصالون', subtitle: 'يظهر للزبائن في «حول الصالون»'),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : PageBody(onRefresh: _load, children: [
                  const PendingActivationBanner(),
                  if (_error != null) SaloniBanner(tone: SaloniBannerTone.warning, body: errorText(_error!)),
                  Row(children: [
                    Container(
                      width: 64,
                      height: 64,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(color: c.primary, borderRadius: SaloniRadius.lgAll),
                      alignment: Alignment.center,
                      child: (_logo ?? '').isNotEmpty
                          ? Image.network(_url(_logo!), fit: BoxFit.cover, width: 64, height: 64,
                              errorBuilder: (_, __, ___) => Text(initial,
                                  style: SaloniTextStyles.title1.copyWith(color: c.onPrimary)))
                          : Text(initial,
                              style: SaloniTextStyles.title1.copyWith(color: c.onPrimary, fontSize: 28)),
                    ),
                    const SizedBox(width: 12),
                    SaloniButton(
                      label: 'تغيير الشعار',
                      icon: SaloniIconName.image,
                      size: SaloniButtonSize.sm,
                      variant: SaloniButtonVariant.secondary,
                      onPressed: uploadsBlocked ? null : () => _upload(logo: true),
                    ),
                  ]),
                  if (uploadsBlocked)
                    const Muted('يمكنك إضافة الشعار والصور بعد تفعيل الصالون.'),
                  SaloniTextField(label: 'اسم الصالون', controller: _name),
                  SaloniTextField(label: 'النبذة', controller: _about),
                  SaloniTextField(label: 'العنوان', controller: _address),
                  SaloniButton(
                    label: _lat == null
                        ? 'تحديد الموقع من مكاني الحالي'
                        : 'الموقع محدد — تحديثه من مكاني الحالي',
                    icon: SaloniIconName.mapPin,
                    variant: SaloniButtonVariant.secondary,
                    block: true,
                    onPressed: _locate,
                  ),
                  SaloniTextField(
                      label: 'هاتف الصالون',
                      controller: _phone,
                      type: SaloniTextFieldType.tel,
                      textDirection: TextDirection.ltr,
                      help: HelpTexts.salonPhone),
                  // ملاحظة التجربة: لا بادئة دولة ثابتة — يكتب المدير الرقم الدولي
                  // كاملًا بأي رمز دولة (E.164)، ويُفتح wa.me بأرقامه دون «+».
                  SaloniTextField(
                      label: 'واتساب (اختياري)',
                      controller: _whatsapp,
                      placeholder: '+970 59 123 4567',
                      type: SaloniTextFieldType.tel,
                      textDirection: TextDirection.ltr,
                      error: _whatsappError,
                      help: HelpTexts.whatsapp),
                  SaloniTextField(
                      label: 'إنستغرام (اختياري)',
                      controller: _instagram,
                      textDirection: TextDirection.ltr,
                      placeholder: '@salon'),
                  SaloniButton(
                    label: 'حفظ الملف',
                    block: true,
                    loading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                  Section(
                    title: 'الصور',
                    trailing: Muted(digits('${_photos.length} من 6')),
                    children: [
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final p in _photos)
                          GestureDetector(
                            onLongPress: () => _deletePhoto(p),
                            child: Stack(children: [
                              Container(
                                width: 96,
                                height: 96,
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color: c.surfaceElevated,
                                  borderRadius: SaloniRadius.mdAll,
                                  border: Border.all(color: c.line),
                                ),
                                child: Image.network(
                                  _url(str(p, ['url', 'path'])),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      Center(child: SaloniIcon(SaloniIconName.image, color: c.inkSubtle)),
                                ),
                              ),
                              PositionedDirectional(
                                top: 0,
                                end: 0,
                                child: IconButton(
                                  tooltip: 'حذف',
                                  onPressed: () => _deletePhoto(p),
                                  icon: SaloniIcon(SaloniIconName.xCircle, color: c.ink, size: 20),
                                ),
                              ),
                            ]),
                          ),
                      ]),
                      if (_photos.length < 6)
                        SaloniButton(
                          label: 'إضافة صورة',
                          icon: SaloniIconName.plus,
                          variant: SaloniButtonVariant.ghost,
                          block: true,
                          onPressed: uploadsBlocked ? null : () => _upload(logo: false),
                        ),
                    ],
                  ),
                  Section(
                      title: 'الخدمات والمنتجات',
                      trailing: const SaloniHelpHint(HelpTexts.catalogVsService),
                      children: [
                    const Muted('تظهر للزبائن بأسعارها ووصفها. المنتجات للعرض فقط.'),
                    for (final item in _catalog)
                      InkWell(
                        borderRadius: SaloniRadius.lgAll,
                        onTap: () async {
                          if (await editCatalogItem(context, ref, item, _services, cur)) _load();
                        },
                        child: CatalogItem(
                          kind: str(item, ['kind', 'type']) == 'product'
                              ? SaloniCatalogKind.product
                              : SaloniCatalogKind.service,
                          name: str(item, ['name'], '—'),
                          price: cur.amount(intOf(item, ['price', 'priceCents']) ?? 0),
                          currency: cur.symbol,
                          description: str(item, ['description']).isEmpty ? null : str(item, ['description']),
                          features: [
                            for (final f in (item['features'] is List ? item['features'] as List : const []))
                              f.toString(),
                          ],
                          minutes: _minutesFor(item),
                          imageProvider: str(item, ['photo']).isEmpty
                              ? null
                              : NetworkImage(_url(str(item, ['photo']))),
                        ),
                      ),
                    SaloniButton(
                      label: 'إضافة خدمة أو منتج',
                      icon: SaloniIconName.plus,
                      variant: SaloniButtonVariant.ghost,
                      block: true,
                      onPressed: () async {
                        if (await editCatalogItem(context, ref, null, _services, cur)) _load();
                      },
                    ),
                  ]),
                  Section(
                      title: 'الخدمات القابلة للحجز',
                      trailing: const SaloniHelpHint(HelpTexts.catalogVsService),
                      children: [
                    const Muted('المدة الأساسية والسعر اللذان يعتمد عليهما الحجز والتقدير.'),
                    GroupBox(children: [
                      if (_services.isEmpty) const ValueRow(first: true, label: 'لا خدمات بعد', value: ''),
                      for (var i = 0; i < _services.length; i++)
                        ValueRow(
                          first: i == 0,
                          label: '${str(_services[i], ['name'], '—')}${_services[i]['active'] == false ? ' (موقوفة)' : ''}',
                          value:
                              '${minutesAr(intOf(_services[i], ['durationMinutes', 'baseDurationMin', 'durationMin']) ?? 0)} · ${cur.format(intOf(_services[i], ['price', 'priceCents']) ?? 0)}',
                          onTap: () async {
                            if (await editService(context, ref, _services[i], cur)) _load();
                          },
                        ),
                    ]),
                    SaloniButton(
                      label: 'إضافة خدمة قابلة للحجز',
                      icon: SaloniIconName.plus,
                      variant: SaloniButtonVariant.ghost,
                      block: true,
                      onPressed: () async {
                        if (await editService(context, ref, null, cur)) _load();
                      },
                    ),
                  ]),
                ]),
        ),
      ],
    );
  }

  int? _minutesFor(Map<String, dynamic> item) {
    final sid = str(item, ['serviceId']);
    if (sid.isEmpty) return intOf(item, ['durationMinutes', 'durationMin']);
    for (final s in _services) {
      if (str(s, ['id']) == sid) return intOf(s, ['durationMinutes', 'baseDurationMin', 'durationMin']);
    }
    return null;
  }
}

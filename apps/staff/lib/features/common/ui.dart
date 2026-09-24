import 'package:flutter/material.dart';
import 'package:saloni_api/saloni_api.dart' as sa;
import 'package:saloni_ui/saloni_ui.dart';

/// عناصر تخطيط مشتركة تطابق النموذج الأولي (appbar/section/bottombar في
/// `design/prototype/generate.py`) — مبنية من رموز `saloni_ui` فقط.

/// رأس الشاشة: عنوان + سطر فرعي + زر رجوع اختياري + عنصر جانبي.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
          SaloniSpacing.space4, SaloniSpacing.space4, SaloniSpacing.space4, SaloniSpacing.space2),
      child: Row(
        children: [
          if (onBack != null) ...[
            Semantics(
              button: true,
              label: 'رجوع',
              child: Material(
                color: c.surfaceRaised,
                shape: RoundedRectangleBorder(
                  borderRadius: SaloniRadius.mdAll,
                  side: BorderSide(color: c.line),
                ),
                child: InkWell(
                  borderRadius: SaloniRadius.mdAll,
                  onTap: onBack,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: SaloniIcon(SaloniIconName.caretRight, color: c.ink, mirrorInRtl: false),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: SaloniSpacing.space3),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: SaloniTextStyles.title1.copyWith(color: c.ink, fontSize: 24, height: 34 / 24),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: SaloniTextStyles.caption.copyWith(color: c.inkMuted),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: SaloniSpacing.space3),
            Flexible(child: trailing!),
          ],
        ],
      ),
    );
  }
}

/// عنوان قسم (h2 في النموذج).
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    final title = Text(
      text,
      style: SaloniTextStyles.title3.copyWith(color: c.ink, fontSize: 18, height: 28 / 18),
    );
    if (trailing == null) return title;
    return Row(
      children: [
        Expanded(child: title),
        trailing!,
      ],
    );
  }
}

/// قسم: عنوان + محتوى بفاصل 10.
class Section extends StatelessWidget {
  const Section({super.key, required this.title, required this.children, this.trailing});
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(title, trailing: trailing),
        for (final w in children) ...[const SizedBox(height: 10), w],
      ],
    );
  }
}

/// محتوى قابل للتمرير بحواف النموذج (16) وفاصل 20 بين العناصر.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.onRefresh, this.gap = 20});
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(
          SaloniSpacing.space4, SaloniSpacing.space2, SaloniSpacing.space4, SaloniSpacing.space6),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          children[i],
        ],
      ],
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

/// شريط سفلي للأزرار الأساسية (bottombar في النموذج).
class BottomActions extends StatelessWidget {
  const BottomActions({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: c.surface,
        border: BorderDirectional(top: BorderSide(color: c.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// بطاقة سطحية (surface-raised + line + radius lg) كما في بطاقات النموذج.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.padding, this.onTap});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Material(
      color: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: SaloniRadius.lgAll,
        side: BorderSide(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(SaloniSpacing.space4),
          child: child,
        ),
      ),
    );
  }
}

/// صف مفتاح/قيمة (صفوف الإعدادات في M-Settings).
class ValueRow extends StatelessWidget {
  const ValueRow({super.key, required this.label, required this.value, this.onTap, this.first = false});
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Material(
      color: c.surfaceRaised,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: SaloniSizes.controlMd),
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: BorderDirectional(top: first ? BorderSide.none : BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              Expanded(child: Text(label, style: SaloniTextStyles.body.copyWith(color: c.ink))),
              const SizedBox(width: SaloniSpacing.space2),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: SaloniTextStyles.body.copyWith(color: c.primary, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// مجموعة صفوف داخل إطار واحد بزوايا 16.
class GroupBox extends StatelessWidget {
  const GroupBox({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: SaloniRadius.lgAll,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

/// نص ثانوي صغير.
class Muted extends StatelessWidget {
  const Muted(this.text, {super.key, this.center = false});
  final String text;
  final bool center;
  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: center ? TextAlign.center : TextAlign.start,
        style: SaloniTextStyles.caption.copyWith(color: context.saloniColors.inkMuted),
      );
}

/// ورقة سفلية بأسلوب النموذج (S-Late / S-Edit): surface-raised، زوايا 22.
Future<T?> showSaloniSheet<T>(BuildContext context, WidgetBuilder builder) {
  final c = context.saloniColors;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: c.surfaceRaised,
    barrierColor: c.overlay,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(SaloniRadius.xl)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 16, 28),
        child: builder(ctx),
      ),
    ),
  );
}

/// رسالة قصيرة أسفل الشاشة.
void toast(BuildContext context, String text) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(content: Text(text)));
}

String errorText(Object e) {
  if (e is sa.ApiError) {
    if (e.code == 'NETWORK_ERROR' || e.code == 'TIMEOUT') {
      return 'تعذّر الاتصال بالسيرفر. تحقق من الإنترنت وحاول مجددًا.';
    }
    return e.message;
  }
  if (e is StateError) return e.message;
  return 'حدث خطأ غير متوقع';
}

/// حوار تأكيد بأزرار نظام التصميم.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
  bool danger = false,
}) async {
  final ok = await showSaloniSheet<bool>(context, (ctx) {
    final c = ctx.saloniColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: SaloniTextStyles.title2.copyWith(color: c.ink)),
        const SizedBox(height: 8),
        Text(body, style: SaloniTextStyles.body.copyWith(color: c.inkMuted)),
        const SizedBox(height: 20),
        SaloniButton(
          label: confirm,
          size: SaloniButtonSize.lg,
          block: true,
          variant: danger ? SaloniButtonVariant.danger : SaloniButtonVariant.primary,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
        const SizedBox(height: 10),
        SaloniButton(
          label: 'تراجع',
          variant: SaloniButtonVariant.ghost,
          block: true,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
      ],
    );
  });
  return ok ?? false;
}

/// محمّل بيانات بسيط: تحميل / خطأ مع إعادة المحاولة / محتوى.
class AsyncView<T> extends StatefulWidget {
  const AsyncView({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;

  @override
  State<AsyncView<T>> createState() => _AsyncViewState<T>();
}

class _AsyncViewState<T> extends State<AsyncView<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    }
    if (_error != null && _data == null) {
      return ListView(
        children: [
          EmptyState(
            icon: SaloniIconName.wifiSlash,
            title: 'تعذّر التحميل',
            body: errorText(_error!),
            action: SaloniButton(label: 'إعادة المحاولة', variant: SaloniButtonVariant.secondary, onPressed: _reload),
          ),
        ],
      );
    }
    return widget.builder(context, _data as T, _reload);
  }
}

/// قراءة متسامحة من JSON خام.
String str(Object? m, List<String> keys, [String fallback = '']) {
  if (m is! Map) return fallback;
  for (final k in keys) {
    final v = m[k];
    if (v != null && v.toString().isNotEmpty) return v.toString();
  }
  return fallback;
}

int? intOf(Object? m, List<String> keys) {
  if (m is! Map) return null;
  for (final k in keys) {
    final v = m[k];
    if (v is num) return v.round();
    if (v is String) {
      final p = int.tryParse(v);
      if (p != null) return p;
    }
  }
  return null;
}

List<Map<String, dynamic>> listOf(Object? v, [List<String> keys = const []]) {
  Object? src = v;
  if (v is Map) {
    for (final k in keys) {
      if (v[k] is List) {
        src = v[k];
        break;
      }
    }
  }
  if (src is! List) return const [];
  return [
    for (final e in src)
      if (e is Map) Map<String, dynamic>.from(e),
  ];
}

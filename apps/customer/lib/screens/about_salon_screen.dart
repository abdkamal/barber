import 'package:flutter/material.dart';
import 'package:saloni_api/saloni_api.dart' as api;
import 'package:saloni_ui/saloni_ui.dart' as ui;
import 'package:url_launcher/url_launcher.dart';

import '../services/customer_api.dart';
import '../widgets/format.dart';

/// «حول الصالون» — تُعرض قبل التسجيل وتبقى متاحة بعده (ق37، design.md §1).
class AboutSalonScreen extends StatefulWidget {
  const AboutSalonScreen({
    super.key,
    required this.api,
    required this.salonCode,
    this.onContinue,
    this.showContinueCta = true,
  });

  final CustomerApi api;
  final String salonCode;

  /// «سجّل واحجز دوري» — يُخفى إن كانت الشاشة تُعرض من داخل التطبيق بعد الدخول.
  final VoidCallback? onContinue;
  final bool showContinueCta;

  @override
  State<AboutSalonScreen> createState() => _AboutSalonScreenState();
}

class _AboutSalonScreenState extends State<AboutSalonScreen> {
  late Future<api.SalonPublicProfile> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getSalonProfile(widget.salonCode);
  }

  Future<void> _retry() async {
    setState(() {
      _future = widget.api.getSalonProfile(widget.salonCode);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<api.SalonPublicProfile>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _ErrorView(onRetry: _retry, message: '${snap.error}');
            }
            final profile = snap.data!;
            return _Loaded(
              profile: profile,
              media: widget.api.mediaUrl,
              onContinue: widget.onContinue,
              showContinueCta: widget.showContinueCta,
            );
          },
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry, required this.message});
  final VoidCallback onRetry;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ui.EmptyState(
        icon: ui.SaloniIconName.storefront,
        title: 'تعذّر تحميل بيانات الصالون',
        body: message,
        action: ui.SaloniButton(label: 'إعادة المحاولة', onPressed: onRetry),
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.profile,
    required this.media,
    required this.onContinue,
    required this.showContinueCta,
  });

  final api.SalonPublicProfile profile;
  final String? Function(String?) media;
  final VoidCallback? onContinue;
  final bool showContinueCta;

  String? get _instagramHandle {
    for (final link in profile.contact.socialLinks) {
      if (link.platform.toLowerCase().contains('instagram') || link.url.contains('instagram')) {
        return link.url;
      }
    }
    return null;
  }

  Future<void> _launch(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final catalogServices = profile.catalog.where((c) => c.type == api.CatalogItemType.service && c.visible).toList();
    // بلا كتالوج خدمات بعد: تُعرض الخدمات القابلة للحجز نفسها.
    final services = catalogServices.isNotEmpty
        ? catalogServices
        : [
            for (final s in profile.services)
              api.CatalogItem(
                id: s.id,
                type: api.CatalogItemType.service,
                name: s.name,
                priceCents: s.priceCents,
                serviceId: s.id,
              ),
          ];
    final products = profile.catalog.where((c) => c.type == api.CatalogItemType.product && c.visible);
    final now = DateTime.now();
    final todayWeekday = now.weekday % 7; // Dart: 1=Mon..7=Sun -> نحوّل الأحد=0
    // الأيام الغائبة من `hours` مغلقة؛ العرض يبدأ بالسبت كما في التصميم.
    final byDay = {for (final h in profile.hours) h.weekday: h};
    final days = profile.hours.isEmpty
        ? const <ui.SaloniHoursDay>[]
        : [
            for (final w in const [6, 0, 1, 2, 3, 4, 5])
              if (byDay[w] case final h?)
                ui.SaloniHoursDay(
                  day: weekdayNameArabic(w),
                  from: formatClockFromMinutes(h.openMinutes),
                  to: formatClockFromMinutes(h.closeMinutes),
                  today: w == todayWeekday,
                )
              else
                ui.SaloniHoursDay(day: weekdayNameArabic(w), closed: true, today: w == todayWeekday),
          ];
    final cover = profile.photos.isEmpty ? null : media(profile.photos.first.url);
    final logo = media(profile.logoUrl);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 160,
          leading: const BackButton(),
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              alignment: Alignment.center,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: cover == null
                  ? Text('[صور الصالون]', style: Theme.of(context).textTheme.bodySmall)
                  : Image.network(cover, fit: BoxFit.cover, width: double.infinity),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  logo == null
                      ? ui.SaloniAvatar(name: profile.name, size: 72)
                      : ClipOval(
                          child: Image.network(logo, width: 72, height: 72, fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => ui.SaloniAvatar(name: profile.name, size: 72)),
                        ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(profile.name, style: Theme.of(context).textTheme.headlineSmall),
                        if (profile.hours.isNotEmpty)
                          Text(profile.openNow ? 'مفتوح الآن' : 'مغلق الآن',
                              style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (profile.about != null) ...[
                Text(profile.about!, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
              ],
              ui.ContactBar(
                address: profile.address,
                phone: profile.contact.phone,
                whatsapp: profile.contact.whatsapp,
                showMaps: profile.hasLocation || profile.address != null,
                instagram: _instagramHandle,
                onCall: profile.contact.phone == null
                    ? null
                    : () => _launch(Uri(scheme: 'tel', path: profile.contact.phone)),
                onWhatsapp: profile.contact.whatsapp == null
                    ? null
                    : () => _launch(Uri.parse('https://wa.me/${profile.contact.whatsapp!.replaceAll('+', '')}')),
                onMaps: () {
                  final uri = profile.latitude != null && profile.longitude != null
                      ? Uri.parse('https://www.google.com/maps/search/?api=1&query=${profile.latitude},${profile.longitude}')
                      : Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(profile.address ?? profile.name)}');
                  _launch(uri);
                },
                onInstagram: _instagramHandle == null ? null : () => _launch(Uri.parse(_instagramHandle!)),
              ),
              const SizedBox(height: 20),
              if (services.isNotEmpty) ...[
                Text('الخدمات', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                for (final s in services)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ui.CatalogItem(
                      kind: ui.SaloniCatalogKind.service,
                      name: s.name,
                      price: s.priceCents == null ? '—' : (s.priceCents! / 100).toStringAsFixed(0),
                      currency: profile.currency,
                      description: s.description,
                      features: s.features,
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              if (products.isNotEmpty) ...[
                Text('المنتجات', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                for (final p in products)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ui.CatalogItem(
                      kind: ui.SaloniCatalogKind.product,
                      name: p.name,
                      price: p.priceCents == null ? '—' : (p.priceCents! / 100).toStringAsFixed(0),
                      currency: profile.currency,
                      description: p.description,
                      features: p.features,
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              if (days.isNotEmpty) ui.HoursList(days: days),
              if (showContinueCta) ...[
                const SizedBox(height: 24),
                ui.SaloniButton(
                  label: 'سجّل واحجز دوري',
                  size: ui.SaloniButtonSize.lg,
                  block: true,
                  onPressed: onContinue,
                ),
              ],
            ]),
          ),
        ),
      ],
    );
  }
}

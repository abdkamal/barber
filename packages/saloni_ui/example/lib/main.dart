import 'package:flutter/material.dart';
import 'package:saloni_ui/saloni_ui.dart';

void main() => runApp(const GalleryApp());

/// معرض مكوّنات «صالوني» — يعرض كل عنصر في الحزمة بالوضعين الداكن والفاتح،
/// باتجاه RTL (والقدرة على التبديل إلى LTR للفحص)، بنصوص عربية من معاينات
/// المكوّنات في `design/design-system/components`.
class GalleryApp extends StatefulWidget {
  const GalleryApp({super.key});

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  bool _dark = true;
  TextDirection _dir = TextDirection.rtl;
  double _textScale = 1.0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'معرض صالوني',
      theme: SaloniTheme.dark(),
      home: Directionality(
        textDirection: _dir,
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(_textScale)),
            child: Theme(
              data: _dark ? SaloniTheme.dark() : SaloniTheme.light(),
              child: _GalleryScaffold(
                dark: _dark,
                dir: _dir,
                textScale: _textScale,
                onToggleDark: () => setState(() => _dark = !_dark),
                onToggleDir: () => setState(
                  () => _dir = _dir == TextDirection.rtl
                      ? TextDirection.ltr
                      : TextDirection.rtl,
                ),
                onTextScale: (v) => setState(() => _textScale = v),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryScaffold extends StatelessWidget {
  const _GalleryScaffold({
    required this.dark,
    required this.dir,
    required this.textScale,
    required this.onToggleDark,
    required this.onToggleDir,
    required this.onTextScale,
  });

  final bool dark;
  final TextDirection dir;
  final double textScale;
  final VoidCallback onToggleDark;
  final VoidCallback onToggleDir;
  final ValueChanged<double> onTextScale;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Scaffold(
      appBar: AppBar(
        title: const Text('معرض «صالوني»'),
        actions: [
          IconButton(
            tooltip: dir == TextDirection.rtl ? 'التبديل إلى LTR' : 'التبديل إلى RTL',
            icon: const Icon(Icons.swap_horiz),
            onPressed: onToggleDir,
          ),
          IconButton(
            tooltip: dark ? 'الوضع الفاتح' : 'الوضع الداكن',
            icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: onToggleDark,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(SaloniSpacing.space4),
        children: [
          Row(
            children: [
              const Text('تكبير النص'),
              Expanded(
                child: Slider(
                  value: textScale,
                  min: 1,
                  max: 1.5,
                  divisions: 5,
                  label: textScale.toStringAsFixed(2),
                  onChanged: onTextScale,
                ),
              ),
            ],
          ),
          const SizedBox(height: SaloniSpacing.space4),
          const _Section(
            title: 'الأزرار',
            child: _ButtonsDemo(),
          ),
          const _Section(title: 'حقل الإدخال', child: _TextFieldsDemo()),
          const _Section(title: 'المجموعة المقسّمة', child: _SegmentedDemo()),
          const _Section(title: 'شرائح الخدمات', child: _ServiceChipsDemo()),
          const _Section(title: 'شارات الحالة', child: _StatusBadgesDemo()),
          const _Section(
            title: 'الصور الرمزية',
            child: Wrap(
              spacing: SaloniSpacing.space3,
              children: [
                SaloniAvatar(name: 'محمد العتيبي'),
                SaloniAvatar(name: 'خالد', tone: SaloniAvatarTone.steel),
                SaloniAvatar(name: 'سارة القحطاني', size: 56),
              ],
            ),
          ),
          const _Section(title: 'اختيار الحلاق', child: _BarberOptionsDemo()),
          const _Section(
            title: 'بطاقة الوقت المتوقع',
            child: Column(
              children: [
                EtaCard(
                  eta: '10:40',
                  barber: 'خالد',
                  services: 'حلاقة شعر ولحية · 45 دقيقة',
                  updated: 'قبل دقيقة',
                ),
                SizedBox(height: SaloniSpacing.space4),
                EtaCard(
                  eta: '10:40',
                  barber: 'خالد',
                  services: 'حلاقة شعر ولحية',
                  originalEta: '10:20',
                  reason: 'تمديد خدمة سابقة',
                  live: false,
                  staleFor: '12 دقيقة',
                ),
              ],
            ),
          ),
          const _Section(
            title: 'تقدّم الطابور (بلا أرقام)',
            child: QueueProgress(
              done: 3,
              ahead: 2,
              updated: 'قبل دقيقة',
              note: 'يشمل استراحة الحلاق القادمة',
            ),
          ),
          const _Section(
            title: 'عناصر الطابور',
            child: Column(
              children: [
                QueueItem(
                  position: 1,
                  name: 'محمد العتيبي',
                  services: 'حلاقة شعر ولحية · 45 دقيقة',
                  eta: '10:40',
                  status: BookingStatus.inService,
                ),
                SizedBox(height: SaloniSpacing.space2),
                QueueItem(
                  position: 2,
                  name: 'عبدالله المطيري',
                  services: 'حلاقة شعر · 30 دقيقة',
                  eta: '11:15',
                  duration: '30 د',
                  status: BookingStatus.called,
                ),
                SizedBox(height: SaloniSpacing.space2),
                QueueItem(
                  position: 3,
                  name: 'سعيد الحربي',
                  services: 'حلاقة شعر وتشذيب لحية',
                  eta: '11:45',
                  requested: true,
                  requestedAt: '11:45',
                  walkIn: true,
                ),
              ],
            ),
          ),
          _Section(
            title: 'بطاقة الخدمة الجارية',
            child: CurrentServiceCard(
              customer: 'محمد العتيبي',
              services: 'حلاقة شعر ولحية',
              startedAt: '10:40',
              elapsed: 50,
              estimate: 45,
              onEnd: () {},
              onEdit: () {},
            ),
          ),
          _Section(
            title: 'عرض أقرب وقت متاح',
            child: OfferCard(
              requested: '10:00',
              offered: '10:40',
              barber: 'خالد',
              secondsLeft: 95,
              onAccept: () {},
              onDecline: () {},
            ),
          ),
          const _Section(
            title: 'أثر التغيير',
            child: ImpactList(
              note: 'سيصل الجميع تنبيه بالتغيير.',
              items: [
                ImpactItem(
                  name: 'أحمد',
                  from: '11:00',
                  to: '11:20',
                  delta: 20,
                  notify: true,
                ),
                ImpactItem(name: 'سالم', from: '11:30', to: '11:50', delta: 20),
                ImpactItem(name: 'فهد', from: '12:00', to: '12:20', pastClosing: true),
              ],
            ),
          ),
          const _Section(
            title: 'الإشعارات',
            child: Column(
              children: [
                SaloniBanner(title: 'معلومة', body: 'سيصلك تنبيه عندما يقترب دورك.'),
                SizedBox(height: SaloniSpacing.space2),
                SaloniBanner(
                  tone: SaloniBannerTone.success,
                  title: 'تم تأكيد الحجز',
                ),
                SizedBox(height: SaloniSpacing.space2),
                SaloniBanner(
                  tone: SaloniBannerTone.warning,
                  title: 'اقترب دورك',
                  body: 'توجه إلى الصالون خلال 10 دقائق.',
                ),
                SizedBox(height: SaloniSpacing.space2),
                SaloniBanner(
                  tone: SaloniBannerTone.danger,
                  title: 'لا يوجد وقت متاح قبل الإغلاق',
                  body: 'جرّب حلاقًا آخر.',
                ),
              ],
            ),
          ),
          const _Section(
            title: 'حالة الاتصال',
            child: Column(
              children: [
                ConnectionBar(),
                SizedBox(height: SaloniSpacing.space2),
                ConnectionBar(state: SaloniConnectionState.syncing, pending: 2),
                SizedBox(height: SaloniSpacing.space2),
                ConnectionBar(
                  state: SaloniConnectionState.offline,
                  since: '10 دقائق',
                  pending: 3,
                ),
              ],
            ),
          ),
          _Section(
            title: 'الإعدادات',
            child: Container(
              decoration: BoxDecoration(
                color: c.surfaceRaised,
                border: Border.all(color: c.line),
                borderRadius: SaloniRadius.lgAll,
              ),
              child: const Column(
                children: [
                  SettingSwitch(
                    label: 'الأرقام العربية',
                    description: 'استخدم ٠-٩ بدل 0-9',
                  ),
                  SettingSwitch(label: 'الإشعارات', checked: true),
                ],
              ),
            ),
          ),
          const _Section(
            title: 'إحصاءات',
            child: Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'الإيراد اليوم',
                    value: '1,240',
                    unit: 'ر.س',
                    delta: '+12% عن أمس',
                    deltaTone: SaloniTone.success,
                    series: [4, 8, 6, 10, 9, 12, 7],
                  ),
                ),
                SizedBox(width: SaloniSpacing.space3),
                Expanded(
                  child: StatTile(
                    label: 'عدد الزبائن',
                    value: '38',
                    delta: '−4% عن أمس',
                    deltaTone: SaloniTone.warning,
                    series: [10, 8, 9, 7, 6, 8, 7],
                  ),
                ),
              ],
            ),
          ),
          const _Section(title: 'حالة فارغة', child: _EmptyStateDemo()),
          const _Section(
            title: 'الكتالوج',
            child: Column(
              children: [
                CatalogItem(
                  kind: SaloniCatalogKind.service,
                  name: 'حلاقة شعر ولحية',
                  price: '60',
                  minutes: 45,
                  description: 'قص وتهذيب مع تشطيب.',
                  features: ['غسيل مجاني'],
                ),
                SizedBox(height: SaloniSpacing.space2),
                CatalogItem(
                  kind: SaloniCatalogKind.product,
                  name: 'شمع تصفيف',
                  price: '35',
                ),
              ],
            ),
          ),
          const _Section(
            title: 'ساعات العمل',
            child: HoursList(
              openNow: true,
              days: [
                SaloniHoursDay(day: 'الأحد', from: '10:00 ص', to: '10:00 م', today: true),
                SaloniHoursDay(day: 'الاثنين', from: '10:00 ص', to: '10:00 م'),
                SaloniHoursDay(day: 'الجمعة', closed: true),
              ],
            ),
          ),
          const _Section(
            title: 'التواصل',
            child: ContactBar(
              address: 'الرياض، حي العليا، شارع التخصصي',
              phone: '+966501234567',
              whatsapp: '+966501234567',
              showMaps: true,
              instagram: '@saloni',
            ),
          ),
          const SizedBox(height: SaloniSpacing.space8),
        ],
      ),
      bottomNavigationBar: SaloniBottomNav(
        active: 0,
        onTap: (_) {},
        items: const [
          SaloniNavItem(icon: SaloniIconName.listNumbers, label: 'الطابور'),
          SaloniNavItem(icon: SaloniIconName.chartBar, label: 'التقارير', badge: 3),
          SaloniNavItem(icon: SaloniIconName.gearSix, label: 'الإعدادات'),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.saloniColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: SaloniSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: SaloniTextStyles.title3.copyWith(color: c.ink),
          ),
          const SizedBox(height: SaloniSpacing.space3),
          child,
        ],
      ),
    );
  }
}

class _ButtonsDemo extends StatelessWidget {
  const _ButtonsDemo();
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: SaloniSpacing.space3,
      runSpacing: SaloniSpacing.space3,
      children: [
        SaloniButton(label: 'احجز دوري', onPressed: () {}),
        SaloniButton(
          label: 'ثانوي',
          variant: SaloniButtonVariant.secondary,
          onPressed: () {},
        ),
        SaloniButton(
          label: 'شبح',
          variant: SaloniButtonVariant.ghost,
          onPressed: () {},
        ),
        SaloniButton(
          label: 'إلغاء الحجز',
          variant: SaloniButtonVariant.danger,
          onPressed: () {},
        ),
        const SaloniButton(label: 'معطّل'),
        const SaloniButton(label: 'جارٍ التحميل', loading: true),
        SaloniButton(
          label: 'إنهاء الخدمة',
          size: SaloniButtonSize.lg,
          icon: SaloniIconName.checkCircle,
          onPressed: () {},
        ),
      ],
    );
  }
}

class _TextFieldsDemo extends StatelessWidget {
  const _TextFieldsDemo();
  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SaloniTextField(
          label: 'رقم الهاتف',
          prefix: '+966',
          placeholder: '5xxxxxxxx',
        ),
        SizedBox(height: SaloniSpacing.space4),
        SaloniTextField(
          label: 'كلمة المرور',
          type: SaloniTextFieldType.password,
        ),
        SizedBox(height: SaloniSpacing.space4),
        SaloniTextField(
          label: 'الاسم',
          error: 'مطلوب',
        ),
      ],
    );
  }
}

class _SegmentedDemo extends StatelessWidget {
  const _SegmentedDemo();
  @override
  Widget build(BuildContext context) {
    return const SaloniSegmentedControl(
      label: 'العرض',
      options: [
        SaloniSegmentedOption(value: 'today', label: 'اليوم'),
        SaloniSegmentedOption(value: 'week', label: 'الأسبوع'),
      ],
    );
  }
}

class _ServiceChipsDemo extends StatelessWidget {
  const _ServiceChipsDemo();
  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        ServiceChip(name: 'حلاقة شعر ولحية', minutes: 45, price: '60', selected: true),
        SizedBox(height: SaloniSpacing.space2),
        ServiceChip(name: 'حلاقة شعر فقط', minutes: 25, price: '35'),
      ],
    );
  }
}

class _StatusBadgesDemo extends StatelessWidget {
  const _StatusBadgesDemo();
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: SaloniSpacing.space2,
      runSpacing: SaloniSpacing.space2,
      children: BookingStatus.values.map((s) => StatusBadge(status: s)).toList(),
    );
  }
}

class _BarberOptionsDemo extends StatelessWidget {
  const _BarberOptionsDemo();
  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        BarberOption(fastest: true, nextAt: '10:40', wait: 'الآن'),
        SizedBox(height: SaloniSpacing.space2),
        BarberOption(name: 'خالد', nextAt: '11:00', wait: 'خلال 20 دقيقة', selected: true),
        SizedBox(height: SaloniSpacing.space2),
        BarberOption(name: 'سعيد', unavailable: true, reason: 'إجازة'),
      ],
    );
  }
}

class _EmptyStateDemo extends StatelessWidget {
  const _EmptyStateDemo();
  @override
  Widget build(BuildContext context) {
    return EmptyState(
      title: 'لا يوجد أحد في الطابور',
      body: 'أضف زبونًا حاضرًا للبدء.',
      action: SaloniButton(label: 'إضافة زبون حاضر', onPressed: () {}),
    );
  }
}

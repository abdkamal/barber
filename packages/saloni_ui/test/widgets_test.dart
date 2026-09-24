import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saloni_ui/saloni_ui.dart';

/// يغلّف [child] بتطبيق مصغّر بثيم «صالوني» واتجاه [dir]، بعرض هاتف (360px)
/// ما لم يُحدَّد غير ذلك.
Widget _harness(
  Widget child, {
  bool dark = true,
  TextDirection dir = TextDirection.rtl,
  double width = 360,
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: dark ? SaloniTheme.dark() : SaloniTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 800),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Directionality(
        textDirection: dir,
        child: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  );
}

/// يتأكد أن لا تجاوز أفقي (overflow) حدث أثناء البناء.
void _expectNoOverflow(WidgetTester tester) {
  final e = tester.takeException();
  if (e != null) {
    // ignore: avoid_print
    print('EXCEPTION DETAIL: $e');
  }
  expect(e, isNull);
}

void main() {
  testWidgets('SaloniButton — الحالات', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _harness(
        Column(
          children: [
            SaloniButton(label: 'احجز دوري', onPressed: () => tapped = true),
            const SaloniButton(
              label: 'ثانوي',
              variant: SaloniButtonVariant.secondary,
            ),
            const SaloniButton(label: 'خطر', variant: SaloniButtonVariant.danger),
            const SaloniButton(label: 'شبح', variant: SaloniButtonVariant.ghost),
            const SaloniButton(label: 'معطّل'),
            const SaloniButton(label: 'تحميل', loading: true),
            const SaloniButton(
              label: 'مع أيقونة',
              icon: SaloniIconName.checkCircle,
              size: SaloniButtonSize.lg,
              block: true,
            ),
          ],
        ),
      ),
    );
    _expectNoOverflow(tester);
    expect(find.text('احجز دوري'), findsOneWidget);
    await tester.tap(find.text('احجز دوري'));
    expect(tapped, isTrue);

    // الزر بلا onPressed معطّل ولا يستجيب.
    await tester.tap(find.text('معطّل'), warnIfMissed: false);
    _expectNoOverflow(tester);
  });

  testWidgets('SaloniTextField — تسمية وبادئة وخطأ', (tester) async {
    await tester.pumpWidget(
      _harness(
        const Column(
          children: [
            SaloniTextField(label: 'رقم الهاتف', prefix: '+966', hint: 'مثال'),
            SaloniTextField(
              label: 'كلمة المرور',
              type: SaloniTextFieldType.password,
            ),
            SaloniTextField(label: 'الاسم', error: 'مطلوب'),
          ],
        ),
      ),
    );
    _expectNoOverflow(tester);
    expect(find.text('رقم الهاتف'), findsOneWidget);
    expect(find.text('مطلوب'), findsOneWidget);
    // زر إظهار كلمة المرور يبدّل الحالة عند الضغط.
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    _expectNoOverflow(tester);
  });

  testWidgets('SaloniSegmentedControl — تبديل الخيار', (tester) async {
    String? changed;
    await tester.pumpWidget(
      _harness(
        SaloniSegmentedControl(
          label: 'العرض',
          options: const [
            SaloniSegmentedOption(value: 'a', label: 'اليوم'),
            SaloniSegmentedOption(value: 'b', label: 'الأسبوع'),
          ],
          onChanged: (v) => changed = v,
        ),
      ),
    );
    _expectNoOverflow(tester);
    await tester.tap(find.text('الأسبوع'));
    await tester.pump();
    expect(changed, 'b');
  });

  testWidgets('ServiceChip — تبديل الاختيار', (tester) async {
    bool? toggled;
    await tester.pumpWidget(
      _harness(
        ServiceChip(
          name: 'حلاقة شعر ولحية',
          minutes: 45,
          price: '60',
          onToggle: (v) => toggled = v,
        ),
      ),
    );
    _expectNoOverflow(tester);
    await tester.tap(find.byType(ServiceChip));
    await tester.pump();
    expect(toggled, isTrue);
  });

  testWidgets('StatusBadge — كل الحالات تعرض نصًا وأيقونة', (tester) async {
    await tester.pumpWidget(
      _harness(
        Wrap(
          children: BookingStatus.values
              .map((s) => StatusBadge(status: s))
              .toList(),
        ),
      ),
    );
    _expectNoOverflow(tester);
    expect(find.byType(StatusBadge), findsNWidgets(BookingStatus.values.length));
  });

  testWidgets('SaloniAvatar — الأحرف الأولى', (tester) async {
    await tester.pumpWidget(_harness(const SaloniAvatar(name: 'محمد العتيبي')));
    _expectNoOverflow(tester);
    expect(find.byType(SaloniAvatar), findsOneWidget);
    expect(find.textContaining('م'), findsWidgets);
  });

  testWidgets('BarberOption — الأسرع وغير متاح', (tester) async {
    await tester.pumpWidget(
      _harness(
        const Column(
          children: [
            BarberOption(fastest: true, nextAt: '10:40', wait: 'الآن'),
            BarberOption(name: 'خالد', nextAt: '11:00', wait: 'خلال 20 د'),
            BarberOption(name: 'سعيد', unavailable: true, reason: 'إجازة'),
          ],
        ),
      ),
    );
    _expectNoOverflow(tester);
    expect(find.text('الأسرع'), findsOneWidget);
    expect(find.text('إجازة'), findsOneWidget);
  });

  testWidgets('EtaCard — عادي وفاتر (stale) بعرض 360 وتكبير نص 1.3', (tester) async {
    await tester.pumpWidget(
      _harness(
        const EtaCard(
          eta: '10:40',
          barber: 'خالد',
          services: 'حلاقة شعر ولحية · 45 دقيقة',
          updated: 'قبل دقيقة',
        ),
        textScale: 1.3,
      ),
    );
    _expectNoOverflow(tester);
    expect(find.text('10:40'), findsOneWidget);

    await tester.pumpWidget(
      _harness(
        const EtaCard(
          eta: '10:40',
          barber: 'خالد',
          services: 'حلاقة شعر ولحية',
          originalEta: '10:20',
          reason: 'تمديد خدمة سابقة',
          live: false,
          staleFor: '12 دقيقة',
        ),
      ),
    );
    _expectNoOverflow(tester);
    expect(find.textContaining('كان متوقعًا'), findsOneWidget);
    expect(find.textContaining('الوقت تقديري'), findsOneWidget);
  });

  testWidgets('QueueProgress — نقاط بلا أرقام', (tester) async {
    await tester.pumpWidget(
      _harness(const QueueProgress(done: 3, ahead: 2, note: 'يشمل استراحة الحلاق')),
    );
    _expectNoOverflow(tester);
    // لا نص رقمي للترتيب — فقط تسمية ووصف.
    expect(find.byType(QueueProgress), findsOneWidget);
  });

  testWidgets('QueueProgress — طابور طويل جدًا (ahead=30) لا يفيض بعرض 360', (tester) async {
    await tester.pumpWidget(
      _harness(const QueueProgress(done: 12, ahead: 30), width: 360),
    );
    _expectNoOverflow(tester);
    expect(find.byType(QueueProgress), findsOneWidget);
  });

  test('QueueProgress.segments — يضغط الزيادة في شريحة واحدة (لا نقاط بلا حد)', () {
    // ضمن الحد: بلا ضغط.
    final small = QueueProgress.segments(done: 3, ahead: 2);
    expect(small, (doneDots: 3, doneCompressed: false, aheadDots: 2, aheadCompressed: false));

    // تجاوز الحد: أقصى 4 منجزة + 6 متبقية، والباقي شريحة واحدة لكل جهة.
    final big = QueueProgress.segments(done: 12, ahead: 30);
    expect(big.doneCompressed, isTrue);
    expect(big.doneDots, QueueProgress.maxDoneDots - 1);
    expect(big.aheadCompressed, isTrue);
    expect(big.aheadDots, QueueProgress.maxAheadDots - 1);
  });

  testWidgets('QueueItem — بعرض 360 مع شارات متعددة', (tester) async {
    await tester.pumpWidget(
      _harness(
        const QueueItem(
          position: 3,
          name: 'عبدالله المطيري',
          services: 'حلاقة شعر · 30 دقيقة',
          eta: '11:15',
          duration: '30 د',
          requested: true,
          requestedAt: '11:15',
          walkIn: true,
          status: BookingStatus.called,
        ),
      ),
    );
    _expectNoOverflow(tester);
  });

  testWidgets('CurrentServiceCard — حالة عادية ومتجاوزة بتكبير نص 1.3', (tester) async {
    var ended = false;
    await tester.pumpWidget(
      _harness(
        CurrentServiceCard(
          customer: 'محمد العتيبي',
          services: 'حلاقة شعر ولحية',
          startedAt: '10:40',
          elapsed: 20,
          estimate: 45,
          onEnd: () => ended = true,
          onEdit: () {},
        ),
        textScale: 1.3,
      ),
    );
    _expectNoOverflow(tester);
    await tester.tap(find.text('إنهاء الخدمة'));
    expect(ended, isTrue);

    await tester.pumpWidget(
      _harness(
        const CurrentServiceCard(
          customer: 'محمد العتيبي',
          services: 'حلاقة شعر ولحية طويلة جدًا لفحص التفاف النص',
          startedAt: '10:40',
          elapsed: 60,
          estimate: 45,
        ),
      ),
    );
    _expectNoOverflow(tester);
    expect(find.textContaining('تجاوزت الخدمة'), findsOneWidget);
  });

  testWidgets('OfferCard — عدّاد وأزرار', (tester) async {
    var accepted = false;
    var declined = false;
    await tester.pumpWidget(
      _harness(
        OfferCard(
          requested: '10:00',
          offered: '10:40',
          barber: 'خالد',
          secondsLeft: 95,
          onAccept: () => accepted = true,
          onDecline: () => declined = true,
        ),
      ),
    );
    _expectNoOverflow(tester);
    await tester.tap(find.text('احجز هذا الوقت'));
    expect(accepted, isTrue);
    await tester.tap(find.text('لا، شكرًا'));
    expect(declined, isTrue);
  });

  testWidgets('ImpactList — عناصر متعددة الحالات', (tester) async {
    await tester.pumpWidget(
      _harness(
        const ImpactList(
          note: 'سيصلهم تنبيه بالتغيير.',
          items: [
            ImpactItem(name: 'أحمد', from: '11:00', to: '11:20', delta: 20, notify: true),
            ImpactItem(name: 'سالم', from: '11:30', to: '11:50', pastClosing: true),
          ],
        ),
      ),
    );
    _expectNoOverflow(tester);
    expect(find.textContaining('بعد الإغلاق'), findsOneWidget);
  });

  testWidgets('SaloniBanner — كل الألوان', (tester) async {
    await tester.pumpWidget(
      _harness(
        const Column(
          children: [
            SaloniBanner(title: 'معلومة', body: 'نص المعلومة'),
            SaloniBanner(tone: SaloniBannerTone.success, title: 'نجاح'),
            SaloniBanner(tone: SaloniBannerTone.warning, title: 'تنبيه'),
            SaloniBanner(tone: SaloniBannerTone.danger, title: 'خطأ'),
          ],
        ),
      ),
    );
    _expectNoOverflow(tester);
  });

  testWidgets('ConnectionBar — الحالات الثلاث', (tester) async {
    await tester.pumpWidget(
      _harness(
        const Column(
          children: [
            ConnectionBar(),
            ConnectionBar(state: SaloniConnectionState.syncing, pending: 2),
            ConnectionBar(
              state: SaloniConnectionState.offline,
              since: '10 دقائق',
              pending: 3,
            ),
          ],
        ),
      ),
    );
    _expectNoOverflow(tester);
    expect(find.textContaining('إضافة زبون حاضر متوقفة'), findsOneWidget);
  });

  testWidgets('SettingSwitch — تبديل الحالة', (tester) async {
    bool? on;
    await tester.pumpWidget(
      _harness(
        SettingSwitch(
          label: 'الأرقام العربية',
          description: 'استخدم ٠-٩ بدل 0-9',
          onChanged: (v) => on = v,
        ),
      ),
    );
    _expectNoOverflow(tester);
    await tester.tap(find.byType(GestureDetector));
    await tester.pump();
    expect(on, isTrue);
  });

  testWidgets('StatTile — مع أعمدة صغيرة', (tester) async {
    await tester.pumpWidget(
      _harness(
        const StatTile(
          label: 'الإيراد اليوم',
          value: '1,240',
          unit: 'ر.س',
          delta: '+12% عن أمس',
          deltaTone: SaloniTone.success,
          series: [4, 8, 6, 10, 9, 12, 7],
        ),
      ),
    );
    _expectNoOverflow(tester);
  });

  testWidgets('SaloniBottomNav — عنصر نشط وشارة', (tester) async {
    int? tappedIndex;
    await tester.pumpWidget(
      _harness(
        SaloniBottomNav(
          active: 1,
          onTap: (i) => tappedIndex = i,
          items: const [
            SaloniNavItem(icon: SaloniIconName.listNumbers, label: 'الطابور'),
            SaloniNavItem(icon: SaloniIconName.chartBar, label: 'التقارير', badge: 3),
            SaloniNavItem(icon: SaloniIconName.gearSix, label: 'الإعدادات'),
          ],
        ),
      ),
    );
    _expectNoOverflow(tester);
    await tester.tap(find.text('الطابور'));
    expect(tappedIndex, 0);
  });

  testWidgets('EmptyState — مع إجراء', (tester) async {
    await tester.pumpWidget(
      _harness(
        EmptyState(
          title: 'لا يوجد أحد في الطابور',
          body: 'أضف زبونًا حاضرًا للبدء.',
          action: SaloniButton(label: 'إضافة زبون', onPressed: () {}),
        ),
      ),
    );
    _expectNoOverflow(tester);
  });

  testWidgets('CatalogItem — خدمة ومنتج', (tester) async {
    await tester.pumpWidget(
      _harness(
        const Column(
          children: [
            CatalogItem(
              kind: SaloniCatalogKind.service,
              name: 'حلاقة شعر ولحية',
              price: '60',
              minutes: 45,
              description: 'قص وتهذيب مع تشطيب',
              features: ['غسيل مجاني'],
            ),
            CatalogItem(
              kind: SaloniCatalogKind.product,
              name: 'شمع تصفيف',
              price: '35',
            ),
          ],
        ),
      ),
    );
    _expectNoOverflow(tester);
  });

  testWidgets('HoursList — يوم مغلق ويوم اليوم', (tester) async {
    await tester.pumpWidget(
      _harness(
        const HoursList(
          openNow: true,
          days: [
            SaloniHoursDay(day: 'الأحد', from: '10:00 ص', to: '10:00 م', today: true),
            SaloniHoursDay(day: 'الجمعة', closed: true),
          ],
        ),
      ),
    );
    _expectNoOverflow(tester);
    expect(find.text('مغلق'), findsOneWidget);
  });

  testWidgets('ContactBar — كل الأزرار', (tester) async {
    await tester.pumpWidget(
      _harness(
        const ContactBar(
          address: 'الرياض، حي العليا',
          phone: '+966501234567',
          whatsapp: '+966501234567',
          showMaps: true,
          instagram: '@saloni',
        ),
      ),
    );
    _expectNoOverflow(tester);
    expect(find.text('اتصال'), findsOneWidget);
    expect(find.text('الاتجاهات'), findsOneWidget);
  });

  group('لا تجاوز أفقي بعرض 360 (RTL) للبطاقات الرئيسية', () {
    testWidgets('EtaCard', (tester) async {
      await tester.pumpWidget(
        _harness(
          const EtaCard(
            eta: '10:40',
            barber: 'خالد بن سالم العتيبي الطويل الاسم',
            services: 'حلاقة شعر ولحية وتشذيب شارب · 45 دقيقة',
          ),
        ),
      );
      _expectNoOverflow(tester);
    });

    testWidgets('CurrentServiceCard', (tester) async {
      await tester.pumpWidget(
        _harness(
          const CurrentServiceCard(
            customer: 'عبدالرحمن بن محمد آل سعيد',
            services: 'حلاقة شعر ولحية وتشذيب شارب وقناع للوجه',
            startedAt: '10:40 ص',
            elapsed: 50,
            estimate: 45,
          ),
        ),
      );
      _expectNoOverflow(tester);
    });

    testWidgets('QueueItem', (tester) async {
      await tester.pumpWidget(
        _harness(
          const QueueItem(
            position: 12,
            name: 'عبدالرحمن بن محمد آل سعيد الطويل',
            services: 'حلاقة شعر ولحية وتشذيب شارب طويل الوصف',
            eta: '11:15 ص',
            duration: '45 دقيقة',
            walkIn: true,
            requested: true,
            requestedAt: '11:15 ص',
          ),
        ),
      );
      _expectNoOverflow(tester);
    });
  });

  testWidgets('السمة الفاتحة (light) تبني بلا أخطاء', (tester) async {
    await tester.pumpWidget(
      _harness(
        const Column(
          children: [
            SaloniButton(label: 'زر'),
            EtaCard(eta: '10:40', barber: 'خالد', services: 'حلاقة شعر'),
          ],
        ),
        dark: false,
        dir: TextDirection.ltr,
      ),
    );
    _expectNoOverflow(tester);
  });

  // Regressions reported by the customer app (overflow in real use).
  testWidgets('OfferCard — اسم حلاق طويل لا يفيض عند 390', (tester) async {
    await tester.pumpWidget(_harness(
      OfferCard(
        requested: '5:00 م',
        offered: '5:25 م',
        barber: 'عبدالرحمن بن عبدالعزيز الحربي',
        secondsLeft: 84,
        total: 120,
        onAccept: () {},
        onDecline: () {},
      ),
      width: 390,
    ));
    _expectNoOverflow(tester);
  });

  testWidgets('ServiceChip — 360 مع تكبير النص 1.3', (tester) async {
    await tester.pumpWidget(_harness(
      ServiceChip(name: 'حلاقة شعر ولحية مع تصفيف', minutes: 45, price: '60', selected: true, onToggle: (_) {}),
      textScale: 1.3,
    ));
    _expectNoOverflow(tester);
  });

  testWidgets('QueueProgress — نص «آخر تحديث» طويل', (tester) async {
    await tester.pumpWidget(_harness(
      const QueueProgress(done: 3, ahead: 2, updated: 'قبل 12 دقيقة من الآن تقريبًا'),
      textScale: 1.3,
    ));
    _expectNoOverflow(tester);
  });
}

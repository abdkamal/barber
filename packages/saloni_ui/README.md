# saloni_ui

نظام التصميم المشترك «صالوني» — حزمة Flutter تضم رموز التصميم (الألوان،
الطباعة، المسافات، الزوايا، الظلال، الأحجام) والمكوّنات المشتركة بين تطبيق
الزبون وتطبيق الطاقم، مبنية من `design/design-system/` (مصدر الحقيقة).

## البنية

```
lib/
  src/tokens/     ألوان (SaloniColors)، طباعة، مسافات، زوايا، ظلال، أحجام
  src/theme/      SaloniTheme.dark() / .light() — ThemeData بمادّة 3
  src/icons/      SaloniIconName + SaloniIcon (Phosphor، وزن regular)
  src/widgets/    كل المكوّنات (انظر index.d.ts في نظام التصميم)
assets/fonts/     El Messiri، IBM Plex Sans Arabic، IBM Plex Mono (مضمّنة)
example/          معرض تفاعلي يعرض كل مكوّن بالوضعين وباتجاهي RTL/LTR
test/             اختبار الرموز (يقارن بـ tokens.json) + اختبارات المكوّنات
```

## الاستخدام

```dart
import 'package:saloni_ui/saloni_ui.dart';

MaterialApp(
  theme: SaloniTheme.dark(), // الافتراضي
  darkTheme: SaloniTheme.dark(),
  // اتجاه RTL مسؤولية التطبيق:
  builder: (context, child) =>
      Directionality(textDirection: TextDirection.rtl, child: child!),
  home: MyHomePage(),
)
```

الوصول إلى الألوان داخل أي واجهة:

```dart
final c = context.saloniColors; // SaloniColors
Container(color: c.surfaceRaised, ...)
```

## الخطوط

الخطوط مضمّنة كملفات (لا تحميل وقت التشغيل)، مرخّصة بموجب SIL Open Font
License 1.1 (نصوص الرخصة في `assets/fonts/licenses/`):

- **El Messiri** (500/600/700، خط متغيّر) — العناوين والأوقات والأرقام الكبيرة.
- **IBM Plex Sans Arabic** (400/500/600) — كل النصوص.
- **IBM Plex Mono** (500) — رمز الصالون ورموز إعادة التعيين.

مصدر الملفات: مستودع [google/fonts](https://github.com/google/fonts) (نفس
الملفات التي توزّعها Google Fonts) عبر `raw.githubusercontent.com`.

## الأيقونات

`phosphor_icons` (منفذ محدَّث من `phosphor_flutter` متوافق مع أن `IconData`
أصبحت `final class` في Flutter 3.43+؛ راجع `pubspec.yaml`)، وزن **regular**
حصرًا، بنفس الأسماء المستخدمة في `components/bundle.js`.

## الاختبارات

```bash
flutter analyze
flutter test
```

`test/tokens_test.dart` يقرأ `design/design-system/tokens.json` مباشرة
ويقارنه بقيم `SaloniColors` / `SaloniSpacing` / `SaloniRadius` / `SaloniSizes`
/ `SaloniTextStyles` — أي تعارض يفشل الاختبار. `test/widgets_test.dart` يبني
كل مكوّن بحالاته الرئيسية، بعرض هاتف 360px واتجاه RTL، ويتحقق من عدم وجود
تجاوز أفقي (overflow) حتى مع تكبير النص 1.3 للبطاقات الرئيسية.

## الاتجاه (RTL)

كل مكوّن يستخدم خصائص اتجاهية (`EdgeInsetsDirectional`،
`AlignmentDirectional`، `BorderDirectional`) بدل left/right المطلقة؛ تحديد
الاتجاه الفعلي (RTL/LTR) مسؤولية التطبيق المستخدم للحزمة، كما هو منصوص في
`design/design-system/README.md`.

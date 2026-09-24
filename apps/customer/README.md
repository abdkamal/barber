# صالوني — تطبيق الزبون (احجز دوري)

تطبيق Flutter للزبون — عربي بالكامل، RTL، Material 3، Riverpod. يعمل **متصلًا
فقط** (لا تخزين محلي للحجوزات)، ويتابع دوره بإشعارات FCM + تحديث دوري كل 30
ثانية أثناء فتح شاشة المتابعة (design.md §10، §5.9، ق31).

## التشغيل

```bash
export PATH=/opt/sdk/flutter/bin:$PATH   # بيئة هذا المستودع
cd apps/customer
flutter pub get
flutter run --dart-define=SALONI_API_BASE_URL=http://<عنوان السيرفر>:3000
```

بلا `--dart-define` يُستخدم `http://10.0.2.2:3000` (مناسب لمحاكي أندرويد
المتصل بسيرفر يعمل على نفس جهاز التطوير).

### الفحوص

```bash
flutter analyze   # نظيف
flutter test      # أخضر
flutter build web # فحص تجميع/تدخين فقط؛ المنتج المستهدف أندرويد
```

بناء APK حقيقي يحتاج Android SDK (غير متوفر في بيئة التطوير الحالية —
`docs/environment.md`)، لذلك لم يُبنَ APK هنا.

## إعداد FCM (Firebase Cloud Messaging)

التطبيق **يعمل بلا `google-services.json`**: عند تعذّر تهيئة Firebase يُكمل
التطبيق عمله بلا إشعارات، ويعرض تحذيرًا عربيًا واضحًا في الشاشة الرئيسية (ق31،
`lib/widgets/notification_warning_banner.dart`) بدل التعطل. المتابعة تبقى
تعمل عبر الاستطلاع الدوري كل 30 ثانية.

لتفعيل الإشعارات فعليًا:
1. أنشئ تطبيق أندرويد في مشروع Firebase بمعرّف الحزمة `sa.saloni.customer`.
2. نزّل `google-services.json` وضعه في `android/app/`.
3. أضف مكوّن Gradle الإضافي في `android/settings.gradle.kts`
   (`id("com.google.gms.google-services") version "..." apply false`) وفعّله
   في `android/app/build.gradle.kts` (`id("com.google.gms.google-services")`).
4. أعد البناء — `NotificationService` سيسجّل رمز FCM تلقائيًا عبر
   `POST /devices` عند أول تشغيل (بعد فحص إذن الإشعارات وتوفر خدمات Google
   Play، design.md §8).

## الشاشات المنفَّذة (design.md §10)

رمز الصالون/QR ← حول الصالون (قبل الدخول) ← تسجيل/دخول (+«الدخول تلقائيًا»،
ق17) ← بانتظار الاعتماد (إن لزم) ← الرئيسية (تبويبات: حجزي، الصالون، السجل،
حسابي) ← الحجز (خدمة أو أكثر، حلاق معيّن أو «الأسرع»، أقرب دور/ساعة محددة،
عرض أقرب وقت مع عدّاد تنازلي دقيقتان) ← المتابعة (الوقت المتوقع، الأصلي
والسبب، شريط التقدّم بلا أرقام، حالة الاستدعاء، «آخر تحديث» دائمًا، حالة
الوقت التقديري عند الانقطاع) ← تعديل الوقت ← إلغاء (تأكيد صريح، ق29) ← السجل
(حالة الدفع) ← الحساب (تسجيل الخروج، المظهر، الصالونات المحفوظة، ق7).

جولة تعريفية مختصرة قابلة للإغلاق تظهر عند أول استخدام لشاشة الحجز
(`lib/widgets/onboarding_tip.dart`، مبدأ السياسة رقم 11)، وتحذير مستقل عند
تعذّر الإشعارات/خدمات Google (ق31).

## البنية

- `lib/services/customer_api.dart` — واجهة `CustomerApi` تفصل الشاشات عن
  `ApiClient` الحقيقي؛ `RealCustomerApi` يفوّض إليه، و`FakeCustomerApi`
  (في `test/fakes/`) يحاكيه في الاختبارات بلا شبكة.
- `lib/services/multi_salon_store.dart` + `salon_scoped_token_store.dart` —
  حساب مستقل لكل صالون على الجهاز (ق7): الجلسات في التخزين الآمن، رمز
  الصالون الفعّال في تفضيلات عادية.
- `lib/providers/session_controller.dart` — آلة حالة الجلسة (Riverpod):
  بلا صالون / بانتظار الاعتماد / جاهز / خطأ.
- `lib/screens/**` — شاشة لكل خطوة في التدفق أعلاه، كل شاشة تأخذ
  `CustomerApi` وبيانات بسيطة كمُدخلات، ما يجعلها قابلة للاختبار مباشرة.

## الربط بالسيرفر

كل الشاشات تستخدم نماذج `saloni_api` المطابقة لما يرسله السيرفر فعلًا (مختبرة على السيرفر
الحقيقي في `e2e/run.sh`):

- **«بانتظار الاعتماد»**: `GET /customer/today` يعيد `accountStatus: pending`، ونقاط الحجز تعيد
  `403 ACCOUNT_PENDING` (`ApiError.isAccountPending`) — كلاهما يقود لشاشة الانتظار.
- **`GET /customer/today`** ← `CustomerToday{services, barbers}`؛ الحلاق غير المتاح (`accepting: false`،
  خارج الدوام، غائب) يظهر معطّلًا بسبب واضح.
- **`GET /bookings/current`** ← `CurrentBooking?`؛ `null` (`{"booking": null}`) يعيد المستخدم لشاشة
  الحجز (انتهت الخدمة أو أُلغي الحجز)، وتعرض المتابعة اسم الحلاق والخدمات وحالة يوم الحلاق.
- **`POST /bookings/{id}/change-time`**: نجاح = نقل ذري. عند `409 SLOT_UNAVAILABLE` يبقى الحجز كما هو
  وتُعرض بطاقة «أقرب وقت» من `error.details.offer` (`ApiError.changeTimeOffer`) بعدّاد تنازلي؛ القبول
  `POST /bookings {offerId}` ينقل الحجز نفسه، والرفض `DELETE /offers/{id}`.
- **`GET /customer/history`** ← `HistoryVisit{booking, barberName, payment?}`: الحلاق والخدمات والمبلغ
  وحالة الدفع (أو حالة الزيارة إن لم تكتمل).
- **«حول الصالون»** ← `SalonPublicProfile` بشكل السيرفر (`about`، `logo`، `hours`، `openNow`،
  `contact.social`، `catalog`؛ تُعرض الخدمات القابلة للحجز إن لم يكن هناك كتالوج)، والصور عبر
  `ApiClient.resolveMediaUrl`.

## ملاحظات

- **منطقة الوقت المعروضة**: الأوقات تُعرض بتوقيت الجهاز المحلي، لا بتوقيت الصالون (`salon.timezone`)
  — تحويل منطقة زمنية دقيق يحتاج حزمة `timezone` غير المضافة هنا (`lib/widgets/format.dart`).
- تم استخدام Navigator إمبراطوري (imperative) بدل `go_router` لتدفق ما قبل الدخول، لأنه تدفق
  تسلسلي بسيط بلا حاجة لروابط عميقة (deep links).
- الخطوط وتراخيصها من `saloni_ui` مباشرة (`registerSaloniFontLicenses()` في `main`).

## متطلب الأندرويد

`android/app/src/main/AndroidManifest.xml` يضيف: `INTERNET` (الاتصال
بالسيرفر)، `CAMERA` (مسح QR عبر `mobile_scanner`)، و`POST_NOTIFICATIONS`
(إذن الإشعارات الصريح على أندرويد 13+). لم يُعدَّل أي ملف Gradle لإضافة
مكوّن Firebase الإضافي (`google-services`) لأن ملف الإعداد غير متوفر — انظر
قسم «إعداد FCM» أعلاه.

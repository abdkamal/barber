# صالوني — الطاقم (`apps/staff`)

تطبيق Flutter للحلاق والمدير (ق35)، أندرويد، عربي فقط مع RTL كامل، الوضع الداكن افتراضي
والفاتح اختياري (ق38). يستخدم حصريًا مكونات ورموز `packages/saloni_ui`، وعميل
`packages/saloni_api` (ApiClient + StaffSyncEngine). المرجع: `docs/design.md` §1، §3، §4، §6، §8،
§10، §11 والنموذج الأولي المعتمد `design/prototype/` (S-*، M-*، S-Signup).

- اسم الحزمة: `sa.saloni.staff` — اسم التطبيق: «صالوني — الطاقم».
- إدارة الحالة: Riverpod (`flutter_riverpod` 2.x) — التنقل: `go_router`.

## التشغيل

```bash
export PATH=/opt/sdk/flutter/bin:$PATH
cd apps/staff
flutter pub get
flutter analyze
flutter test
flutter run -d <android-device> --dart-define=API_BASE_URL=http://10.0.2.2:3000
# فحص تجميع فقط (المنتج أندرويد):
flutter build web --no-web-resources-cdn
```

### متغيرات `--dart-define`

| المتغير | الافتراضي | الوصف |
|---|---|---|
| `API_BASE_URL` | `http://10.0.2.2:3000` | عنوان السيرفر (بدون `/v1`). الافتراضي = سيرفر محلي من محاكي أندرويد. |
| `FCM_ENABLED` | `false` | تفعيل Firebase Cloud Messaging (يتطلب `google-services.json`). |

**HTTP مقابل HTTPS:** `android/app/src/main/res/xml/network_security_config.xml` يمنع HTTP
الصريح إلا لـ `10.0.2.2` و`localhost` (تطوير). لسيرفر التجربة استخدم HTTPS (design §7)؛ ولسيرفر
على شبكة محلية أضف عنوانه مؤقتًا إلى ذلك الملف.

## أندرويد

- `minSdk` = 23 على الأقل (التخزين الآمن، SQLCipher، الخدمة الأمامية).
- الأذونات في `AndroidManifest.xml`: `INTERNET`، `ACCESS_NETWORK_STATE`، `FOREGROUND_SERVICE`،
  `FOREGROUND_SERVICE_SPECIAL_USE`، `WAKE_LOCK`، `POST_NOTIFICATIONS`، `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`،
  `RECEIVE_BOOT_COMPLETED`، `VIBRATE`، والموقع (للمدير فقط عند «تحديد الموقع من مكاني الحالي»).
- **الخدمة الأمامية** (design §1) عبر `flutter_foreground_task` 8.x بإشعار دائم «مزامنة الطابور».
  نوعها `specialUse` لا `dataSync`: أندرويد 15 يحدّ خدمات `dataSync` بست ساعات يوميًا ويوم الحلاق
  أطول. عند النشر على Google Play يلزم تبرير الاستخدام الخاص في Play Console (التطبيق يوزَّع على الطاقم
  فقط — ق35). وظيفة الخدمة إبقاء العملية حيّة؛ النبضة والمزامنة (كل 30 ث) ينفذهما `StaffSyncEngine`
  في المعزول الرئيسي. **حد معروف:** إن أغلق المستخدم التطبيق من قائمة التطبيقات الحديثة يتوقف المعزول
  الرئيسي حتى يُفتح من جديد (تبقى الأحداث محفوظة في الصندوق).
- عند أول تشغيل: فحص إذن الإشعارات وطلبه، وطلب الاستثناء من تحسين البطارية، وتحذير عربي واضح إن رُفض
  الإذن (ق31، §8) مع شريط تحذير دائم في «طابوري».
- **لم يُبنَ APK في هذه البيئة**: Android SDK محجوب (`docs/environment.md`). التحقق الحالي:
  `analyze` + `test` + بناء الويب.

### Firebase (FCM) — اختياري

1. أنشئ مشروع Firebase وأضف تطبيق أندرويد بالمعرّف `sa.saloni.staff`.
2. ضع `google-services.json` في `android/app/` (مستثنى من Git في `.gitignore`).
3. شغّل بـ `--dart-define=FCM_ENABLED=true`.

`android/app/build.gradle.kts` يطبّق إضافة `com.google.gms.google-services` فقط إن وُجد الملف، لذا
يُبنى التطبيق ويعمل كاملًا بدونه (المزامنة الدورية وتنبيه تجاوز المدة داخل التطبيق يبقيان). رمز الجهاز
يُسجَّل عبر `POST /devices`، وإن تعذّرت خدمات Google يُبلَّغ السيرفر `hasPlayServices: false`.

## البنية

```
lib/
  main.dart / app.dart          تهيئة، الثيم، RTL، الموجّه وحراسة الأدوار (/m/* للمدير فقط)
  core/                         config، تنسيق عربي (أرقام مشرقية اختيارية، عملة، أوقات)، تفضيلات،
                                CompatHttpClient، RawApi، platform/ (تخزين، خدمة أمامية، FCM)
  data/                         نماذج العرض، منطق الطابور المحلي، BarberRepository (فوق StaffSyncEngine)
  state/app_services.dart       الخدمات، AuthController، مزوّدات Riverpod
  features/
    auth/                       الدخول (رمز الصالون + المستخدم + كلمة المرور + الدخول تلقائيًا)، رمز إعادة التعيين
    signup/                     تسجيل صالون (4 خطوات) ← «بانتظار التفعيل» (ق37)
    barber/                     طابوري، الزبون المتأخر، تعديل الخدمة + الأثر، قرار الإغلاق، الحاضر،
                                الدفعات، استراحاتي، المزيد
    manager/                    الطوابير + النقل، التقارير، ملف الصالون + الصور + الكتالوج + الخدمات،
                                الإعدادات + QR، الطاقم، الزبائن، الدوام/الاستراحات/الإجازات
    common/                     هياكل التنقل، شريط الاتصال، الجولة التعريفية، عناصر تخطيط
test/                           اختبارات فوق سيرفر وهمي (MockClient) عبر ApiClient الحقيقي
assets/fonts/                   نسخة من خطوط saloni_ui (انظر «تغييرات مطلوبة في الحزم»)
```

## العمل دون اتصال (design §6)

- كل إجراء للحلاق (بدء، إنهاء، تعديل الخدمة، تأجيل، انتظار، لم يحضر، قرار الإغلاق، تأكيد الدفع،
  الاستراحات، «لن أعمل اليوم») يُسجَّل حدثًا في صندوق `StaffSyncEngine` ويُطبَّق محليًا فورًا
  (`data/queue_logic.dart`)؛ الواجهة لا تنتظر الشبكة أبدًا.
- عند كل تحديث من السيرفر يُعاد تطبيق الأحداث غير المرسلة فوق حالته.
- إضافة زبون حاضر ومعاينة الأثر «متصل فقط» (معطّلة برسالة واضحة دون اتصال). تعديل الخدمة نفسه يُقبل
  دون اتصال (ق9).
- التخزين المحلي: `DriftLocalStore` فوق SQLCipher (`saloni_api/flutter.dart`) على الجهاز؛ ذاكرة على الويب.
  الخروج يمسح القاعدة وملفها ومفتاحها ويوقف الخدمة الأمامية. انتهاء الجلسة القسري لا يمسح الأحداث غير
  المرسلة؛ تُمسح إن دخل حساب آخر على الجهاز.

## تغييرات مطلوبة في الحزم (لم تُعدَّل — حلول مؤقتة داخل التطبيق)

| الحزمة | المشكلة | الحل المؤقت هنا |
|---|---|---|
| saloni_api | `Session.fromJson` يتوقع `salon` نصًا، والسيرفر يعيده كائنًا `{code,name,status,timezone,currency}` (+ `account`) — يفشل الدخول والتجديد | `CompatHttpClient` يحوّله إلى الرمز ويحتفظ بالكائن |
| saloni_api | `Booking` لا يحمل `customerName`/`customerPhone`/`eta`/`estimatedDurationMin`/`priceCents`/`calledAt`/`serveLate` التي يرسلها السيرفر؛ و`StaffToday` يُسقط `day`/`walkInOnly`/`closingWarnings` | `CompatHttpClient` يحتفظ بآخر JSON خام لـ `/staff/today` وغيرها |
| saloni_api | رفع الصور multipart (`/manager/photos`، `/manager/profile/logo`، `/manager/catalog/{id}/photo`) بينما `addManagerPhoto` يرسل JSON؛ `PUT /manager/schedules` بينما العميل يرسل POST؛ لا حذف للدوام/الاستراحات/الإجازات؛ لا `GET /manager/phone-disputes` | `core/raw_api.dart` |
| saloni_api | `StaffSyncEngine`: يعيد بث آخر حالة عند تغيّر عدد المعلّق (فتبدو كنتيجة اتصال)؛ `since` يتجدد مع كل نبضة فاشلة؛ لا «إرسال فوري» يتجاوز التراجع الأُسّي؛ النبضة تستهلك رقم تسلسل جهاز؛ لا تحديث للطابور المحلي من التغييرات (onChanges فقط) | معالجة في `BarberRepository` |
| saloni_api | فشل شبكة أثناء تجديد الجلسة بعد 401 يُعامل كخروج (`onSignedOut`) | لا حل؛ يُراجع |
| saloni_ui | الخطوط مسجّلة باسم `packages/saloni_ui/…` بينما الأنماط تطلب الاسم المجرد، فلا تُطبَّق في أي تطبيق | نسخة الخطوط (مع تراخيص OFL) في `assets/fonts` مسجّلة بالاسم المجرد. الحل الصحيح: `package: 'saloni_ui'` في الأنماط |
| saloni_ui | `SaloniTextField` بلا `enabled`/`maxLines`/`keyboardType` مخصص؛ لا عنصر اختيار قائمة | عناصر بسيطة من الرموز نفسها |

## افتراضات (العقد لا يحسمها)

- أشكال `/manager/queues` و`POST /manager/bookings/{id}/transfer` غير منفذة في السيرفر بعد؛ القراءة
  متسامحة (`barberId|barber.id`، `queue|bookings` بحقول BookingDto).
- ساعات الصالون في التسجيل = دوام افتراضي لكل يوم (`staffId: null`) عبر `PUT /manager/schedules`.
- السيرفر لا يعيد صور الصالون في `GET /manager/profile`؛ تُعرض الصور المرفوعة في الجلسة الحالية فقط.
- صور الوسائط تُعرض من `/v1/media/{code}/{file}` (للصالونات المفعّلة فقط).
- «الأرقام العربية المشرقية» تفضيل عرض على الجهاز.
- التوقيت المعروض بتوقيت الجهاز (جهاز الحلاق في الصالون).

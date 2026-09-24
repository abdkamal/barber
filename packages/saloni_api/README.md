# saloni_api

عميل الواجهة البرمجية والنماذج المشتركة بين تطبيقي «صالوني» (الزبون والطاقم).
مصدر الحقيقة للعقد هو `docs/api.md`، مبني وفق `docs/design.md` (§3، §4، §6، §7)
و`docs/decisions.md`.

## نقاط الدخول (Entrypoints)

| المكتبة | الاعتماد | الاستخدام |
|---|---|---|
| `package:saloni_api/saloni_api.dart` | Dart نقي، بلا Flutter | النماذج + `ApiClient` + `TokenStore`/`InMemoryTokenStore`. قابلة للاختبار بـ`dart test` بدون SDK فلاتر. |
| `package:saloni_api/flutter.dart` | Flutter | `SecureStorageTokenStore` (فوق `flutter_secure_storage`)، ومساعدات فتح قاعدة بيانات مطاردة الطاقم بتشفير SQLCipher. |
| `package:saloni_api/staff_sync.dart` | Dart نقي (Drift عبر `NativeDatabase`) | دعم عمل تطبيق الطاقم دون اتصال: `LocalStore`، `DriftLocalStore`، `Outbox`، `MonotonicClock`، `StaffSyncEngine`، `ConnectionState`. |

هذا الفصل مقصود: النواة (النماذج والعميل) يجب أن تبقى قابلة للاختبار بـ
`dart test` دون تثبيت Android SDK، تمامًا كبيئة التطوير الحالية.

## الاستخدام السريع

```dart
import 'package:saloni_api/saloni_api.dart';

final client = ApiClient(
  baseUrl: 'https://salon-server.example.com',
  tokenStore: InMemoryTokenStore(), // أو SecureStorageTokenStore من flutter.dart
);

final profile = await client.getSalonProfile('ABC123');
final session = await client.loginCustomer(
  salonCode: 'ABC123', phone: '0500000000', password: '********',
  rememberMe: true, // ق17: «الدخول تلقائيًا»
);
```

### تجديد الجلسة والخروج

`ApiClient` يجدّد رمز الوصول تلقائيًا عند 401، بمحاولة تجديد واحدة متزامنة
(single-flight) حتى مع طلبات متعددة متزامنة. إن فشل التجديد يُطلق حدثًا على
`client.onSignedOut` ويرمي `ApiError(code: 'SIGNED_OUT')`؛ على التطبيق
الاستماع لهذا التيار وإعادة توجيه المستخدم لشاشة الدخول.

### `Idempotency-Key`

يُولَّد مفتاح UUID v4 تلقائيًا لكل طلب من: إنشاء عرض/حجز (`quote`،
`bookings`)، تعديل الوقت، الإلغاء، إضافة زبون حاضر، ونقل حجز (المدير). إن
أعاد `ApiClient` المحاولة تلقائيًا بعد تجديد الجلسة (401) يعيد استخدام نفس
المفتاح لهذا الطلب. لإعادة محاولة يدوية من التطبيق بعد فشل (مثل انقطاع
مفاجئ)، مرّر `idempotencyKey` صراحة لتُستخدم نفس القيمة.

### 429 ومهلة الاتصال

`ApiClient` يحوّل 429 إلى `ApiError(code: 'RATE_LIMITED', retryAfter: ...)`
مبنيًا على ترويسة `Retry-After`؛ القرار (الانتظار/الإلغاء) متروك للمستدعي.
مهلة كل طلب قابلة للضبط عبر `timeout` (افتراضيًا 15 ثانية) وتُترجم لخطأ
`ApiError(code: 'TIMEOUT')`.

## دعم عمل تطبيق الطاقم دون اتصال (`staff_sync.dart`)

```dart
import 'package:saloni_api/staff_sync.dart';

final store = DriftLocalStore(db); // انظر أدناه لفتح db
final engine = StaffSyncEngine(api: client, store: store);
await engine.start(); // نبضة + سحب كل 30 ث (design.md §11)

engine.connectionState.listen((state) {
  // state.status: online / syncing / offline — لشريط الاتصال الدائم
});

await engine.recordEvent(DeviceEventType.serviceStarted, bookingId: 'b1');

// إضافة زبون حاضر — تُرفض محليًا وفورًا دون اتصال (design.md §10):
await engine.createWalkIn(name: '...', phone: '...', serviceIds: [...]);
```

### الساعة الرتيبة (`MonotonicClock`)

وقت حدوث كل حدث = آخر وقت سيرفر معروف + الوقت المنقضي بـ`Stopwatch` منذ
تثبيته (design.md §6.2). عند استرجاع مرساة محفوظة من تشغيل سابق
(`restoreAnchor`) تُعلَّم كل القراءات `approximate: true` حتى تحدث مزامنة
حقيقية جديدة في هذا التشغيل (`anchor`) — لأن استمرارية `Stopwatch` تُفقد
بإعادة تشغيل التطبيق.

### الصندوق (`Outbox`) وإعادة المحاولة

كل حدث يُحفظ محليًا فور وقوعه، قبل أي محاولة إرسال. `flush()` يرسل الأحداث
المستحقة بترتيب رقم تسلسل الجهاز عبر `POST /sync/events`، ويطابق النتيجة لكل
حدث:
- `applied`/`duplicate` ← يُحذف من الصندوق.
- `rejected` ← يُحذف أيضًا (لا فائدة من إعادة إرسال انتقال غير صالح؛ السيرفر
  سجّله للمدير حسب design.md §6.2).
- فشل شبكة كامل ← تراجع أُسّي (`2s, 4s, 8s, ...` حتى سقف 60 ث) قبل إعادة
  المحاولة.

### التخزين المحلي (`LocalStore`)

- `InMemoryLocalStore`: للاختبارات.
- `DriftLocalStore`: تنفيذ SQLite عبر Drift (جدول مفتاح/قيمة JSON للطابور
  والخدمات والاستراحات والإعدادات ومؤشر المزامنة، وجدول صندوق أحداث منفصل).
  يُبنى فوق أي `QueryExecutor`، لذا يعمل في الاختبارات بـ`NativeDatabase.memory()`
  بلا Flutter.

### التشفير (SQLCipher) — ملاحظة صدق مهمة

المطلوب: SQLCipher بمفتاح من التخزين الآمن. المنفَّذ فعليًا في
`lib/flutter.dart`:
- `staffSyncEncryptionKey()`: يولّد مفتاحًا عشوائيًا (32 بايت) عند أول
  استخدام ويحفظه في `flutter_secure_storage`، منفصلًا عن رمز الجلسة.
- `openEncryptedStaffSyncExecutor(fileName, encryptionKey)`: يفتح
  `NativeDatabase` عبر `sqlcipher_flutter_libs` (`open.overrideFor` +
  `PRAGMA key`) — النمط الموثّق رسميًا لدمج Drift مع SQLCipher.

**ما لم يُختبر:** هذا المسار غير مُتحقَّق منه على جهاز/محاكي أندرويد حقيقي،
لأن Android SDK غير متاح في بيئة التطوير الحالية (`docs/environment.md`).
الاختبارات الآلية (`dart test`) تستخدم `NativeDatabase.memory()` غير المشفّر
عمدًا لتبقى نواة `staff_sync.dart` خالية من اعتماد Flutter. **يجب التحقق من
`openEncryptedStaffSyncExecutor` على جهاز حقيقي في مرحلة تجربة نسخة التطوير
(المرحلة 11) قبل الاعتماد عليه**، والتأكد أن `PRAGMA key` يفتح قاعدة موجودة
غير مشفّرة مسبقًا بشكل متوقع (سيناريو الترقية من نسخة تجريبية غير مشفّرة، إن
وُجد) أو حذفها والبدء من جديد.

### الخروج وإيقاف الحساب

`StaffSyncEngine.wipeOnLogout()` يوقف المؤقتات ويمسح كل شيء من `LocalStore`
(design.md §6.1: «يُمسح عند الخروج أو إيقاف الحساب»). على التطبيق أيضًا مسح
مفتاح SQLCipher عبر `wipeStaffSyncEncryptionKey()` عند نفس الحدث.

## قرارات وافتراضات (لا يحسمها `api.md` صراحة)

هذه اختيارات آمنة اتُّخذت عند غموض العقد، ويجدر تأكيدها مع فريق السيرفر:

1. **شكل `SyncChange`** (`GET /sync?since=`): `api.md` لا يفصّل حقول كل
   تغيير. اعتُمد شكل عام `{seq, type, bookingId?, data, occurredAt}` مرن
   يستوعب أي نوع تغيير يرسله السيرفر لاحقًا.
2. **`Idempotency-Key` على `POST /bookings/quote`**: العقد يذكره صراحة فقط
   لما «ينشئ أو يغيّر حجزًا أو دفعًا»، لكن العرض (`offer`) يحجز مكانًا فعليًا
   (ق13)، فأُضيف احتياطًا لمنع ازدواج حجز العرض عند إعادة الإرسال. كذلك على
   `POST /manager/bookings/{id}/transfer` لأنه يغيّر حجزًا.
3. **مسارات المدير**: لا نماذج Dart مخصّصة لها (غير مطلوبة صراحة في هذه
   المهمة) — `ApiClient` يمرّر/يعيد `Map<String, dynamic>`/`List<dynamic>`
   خامًا لكل مسارات `/manager/*`.
4. **`WS /staff/stream`**: لم يُنفَّذ عميل WebSocket في هذه الحزمة. آلية
   السحب الدورية (`GET /sync?since=` كل 30 ثانية عبر `StaffSyncEngine`) تفي
   بمتطلب المزامنة الأساسي في design.md §6؛ الدفع اللحظي عبر WebSocket
   تحسين إضافي مذكور في design.md §6.3 ولم يُطلب صراحة في نطاق هذه المهمة.
   يُنصح بإضافته لاحقًا لتقليل الكمون بين نبضة وأخرى.
5. **صيغة JSON**: النماذج مكتوبة يدويًا (`toJson`/`fromJson`) بدل
   `json_serializable`/`build_runner` لتبسيط الصيانة وتفادي خطوة بناء إضافية
   للنموذج (النماذج بسيطة نسبيًا). Drift (لصندوق المزامنة) يستخدم
   `build_runner` بالفعل (`dart run build_runner build`) والملفات المولَّدة
   (`*.g.dart`) محفوظة في المستودع.

## الاختبارات

```
dart pub get   # أو: flutter pub get (الحزمة تعتمد على Flutter لـ flutter.dart)
dart run build_runner build   # يولّد drift_database.g.dart عند تعديل الجداول
dart test
dart analyze
```

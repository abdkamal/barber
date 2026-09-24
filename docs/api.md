# عقد الواجهة البرمجية (v1)

مرجع مشترك للسيرفر وتطبيقي Flutter. مشتق من `design.md` (2.1). الأوقات بصيغة ISO-8601 UTC، والمبالغ أعداد صحيحة بأصغر وحدة للعملة (هللة)، والعملة من ملف الصالون.

## قواعد عامة
- كل الطلبات عبر HTTPS تحت `/v1`. الصالون يُستخرج من رمز الجلسة فقط، لا من الطلب (§7).
- الأخطاء: `{"error": {"code": "SLOT_UNAVAILABLE", "message": "نص عربي للعرض", "details"?: …}}` مع حالة HTTP مناسبة. `details` اختياري ويظهر فقط حيث يُذكر أدناه:
  `VALIDATION_FAILED` ← `details = [{path, code, …}]`؛ `SLOT_UNAVAILABLE` من `POST /bookings` ← `details = {nearest, barberId}`، ومن `change-time` ← `details = {offer}`؛ `TRANSFER_NO_SLOT` ← `details = {nearest, alternatives[]}`. التكرار بمفتاح `Idempotency-Key` يعيد `details` كما هو.
- رموز أخطاء الحجز الشائعة: `ACCOUNT_PENDING` (403 — حساب الزبون بانتظار اعتماد الصالون؛ على `quote` و`bookings` و`change-time`)، `ACCOUNT_SUSPENDED` (403 — عند الدخول/التجديد؛ الحساب الموقوف تُلغى جلساته فيصله `401`)، `SERVICE_UNAVAILABLE` (400)، `BARBER_NOT_FOUND` / `BOOKING_NOT_FOUND` / `OFFER_NOT_FOUND` (404)، `BOOKING_CLOSED` / `OUTSIDE_WORKING_HOURS` / `BARBER_ABSENT` / `BARBER_UNAVAILABLE` / `NO_SLOT` / `MAX_ACTIVE_BOOKINGS` / `SLOT_UNAVAILABLE` / `BOOKING_STARTED` / `BOOKING_NOT_ACTIVE` / `BOOKING_CALLED` / `PAST_CLOSING` / `NOT_WORKING_NOW` (409)، `OFFER_EXPIRED` (410)، `IDEMPOTENCY_KEY_REUSED` (422).
- رموز أُضيفت في مراجعة المرحلة 6: `REGISTRATION_FAILED` (409 — يحل محل `PHONE_ALREADY_REGISTERED`)، `REGISTRATION_PAUSED` (503 — تسجيل الصالونات متوقف مؤقتًا)، `SALON_NOT_ACTIVE` (409 — رفع صورة لصالون غير مفعّل)، `OWNER_PROTECTED` / `LAST_MANAGER` (409 — الطاقم)، `PHONE_IN_USE` / `PHONE_RELEASED` (409 — الزبائن).
- الطلبات التي تنشئ أو تغيّر حجزًا أو دفعًا تحمل ترويسة `Idempotency-Key` (UUID)؛ تكرارها يعيد النتيجة الأولى.
- حدود المعدل تعيد `429` مع `Retry-After`. **(الجولة 2، M1)** حدود الدخول والتسجيل وإعادة التعيين صارمة لكل عنوان IP ولكل (حساب + IP)؛ أما حد الحساب الواحد من كل العناوين فهو **إبطاء فقط** (تأخير متدرج للرد بحد أقصى بضع ثوانٍ) ولا يعيد `429` أبدًا — فلا يستطيع أحد قفل حساب مستخدم من عناوين أخرى.
- رموز أُضيفت في الجولة 2: `BOOKING_NOT_UNFINISHED` (409)، `INVALID_END_TIME` (400) — كلاهما من `POST /manager/bookings/{id}/resolve`.
- رمز أُضيف في ق40: `ACCOUNT_NOT_SUSPENDED` (409) — من `POST /manager/staff/{id}/recover-events` لحساب غير موقوف.

## عام (بلا دخول)
| الطلب | الوصف |
|---|---|
| `GET /salons/{code}` | ملف الصالون العام (للصالونات المفعّلة فقط): الاسم، الشعار، النبذة، العنوان، الإحداثيات، وسائل الاتصال، الصور، ساعات العمل، الكتالوج. روابط الصور والشعار بصيغة `/v1/media/{code}/{file}` |
| `GET /media/{code}/{file}` | ملف صورة مخزّن (صور الصالون، الشعار، صور الكتالوج) — للصالونات المفعّلة فقط، وإلا `404`؛ `Cache-Control: public, max-age=86400, immutable` |
| `POST /salons/register` | تسجيل صاحب صالون (ق37) ← صالون `pending_activation` + حساب مدير. يتوقف مؤقتًا (`503 REGISTRATION_PAUSED`) إن بلغ عدد الصالونات بانتظار التفعيل الحد (M4) |

## الدخول
| الطلب | الوصف |
|---|---|
| `POST /auth/customer/register` | `{salonCode, name, phone, password}` ← حساب (`pending` إن كان الاعتماد مطلوبًا) + جلسة. **لا يكشف وجود الرقم (L4):** إن كان للرقم حساب وكلمة المرور تطابقه فهو دخول عادي (`201` بالشكل نفسه، الحساب القائم)؛ وإلا `409 REGISTRATION_FAILED` برسالة عامة («إن كان لديك حساب فسجّل الدخول أو اطلب رمز إعادة التعيين»). |
| `POST /auth/customer/login` | `{salonCode, phone, password}` |
| `POST /auth/staff/login` | `{salonCode, username, password}` |
| `POST /auth/refresh` | `{refreshToken}` ← زوج جديد (تدوير؛ إعادة الاستخدام تلغي العائلة). **مهلة الشبكة المتقطعة (الجولة 2):** إن ضاع رد التدوير وأعاد التطبيق الرمز نفسه خلال **30 ث** من تدويره، وكان هو الرمز **السابق مباشرة** للجلسة (وخلفه لم يُستخدم بعد)، يُعاد له زوج جديد **مرة واحدة فقط** (يُسجَّل في التدقيق `session.refresh_grace_reuse`) بدل إلغاء العائلة؛ ويصبح الخلف والزوج المُعاد «شقيقين» — تدوير أحدهما يُبطل الآخر. أي إعادة استخدام أخرى (بعد المهلة، أو للمرة الثانية، أو لرمز أقدم، أو لشقيق أُبطل) تلغي العائلة كما كانت (`401 REFRESH_TOKEN_REUSED`). المدة `REFRESH_REUSE_GRACE_SEC` (0 = معطلة) |
| `POST /auth/logout` | يلغي رمز التجديد |
| `POST /auth/reset` | `{salonCode, identifier, code, newPassword}` — رمز لمرة واحدة من المدير |

الجلسة: `{accessToken (15 د), refreshToken, role, salon}`. «الدخول تلقائيًا» = حفظ رمز التجديد في التخزين الآمن.

## الزبون
| الطلب | الوصف |
|---|---|
| `GET /customer/today` | الخدمات، الحلاقون وحالتهم وأقرب بدء لكل منهم |
| `POST /bookings/quote` | `{serviceIds[], barberId?, kind: queue\|requested, requestedAt?}` ← `{barberId, start, end, durationMin, price, outcome: accept\|offer, offerId?, offerExpiresAt?}`. العرض يحجز مكانه (ق13) |
| `POST /bookings` | `{serviceIds[], barberId?, kind, requestedAt?}` أو `{offerId}` ← الحجز |
| `DELETE /offers/{id}` | رفض العرض |
| `GET /bookings/current` | الحجز النشط: `{booking, eta, originalEta, lastChangeReason, status, progress: {done, ahead}, live, lastUpdateAt}`؛ وبلا حجز نشط: `200 {booking: null, serverTime}` |
| `POST /bookings/{id}/seen` | `{eta}` — ما عرضه التطبيق فعلًا؛ مرجع التنبيه الإلزامي (ق5). `204` دائمًا، لكن **يُسجَّل فقط إن كان ضمن 5 دقائق من إسقاط السيرفر الحالي** وإلا يُتجاهل (H1)، ولا يدخل أبدًا في إعفاء ق23 (يُحكم فيه بما سجّله السيرفر وحده) — **الجولة 2:** مرجع ق23 يُحفظ منفصلًا ولا يُكتب إلا من أوقات أصدرها السيرفر (تأكيد الحجز، الاستدعاء، تنبيه ق5، التأجيل، النقل، تعديل الوقت)، فلا يغيّره `seen` مهما كانت قيمته |
| `POST /bookings/{id}/change-time` | `{kind, requestedAt?}` ← نقل ذري أو عرض أقرب وقت (§5.12) |
| `POST /bookings/{id}/cancel` | قبل بدء الخدمة فقط (ق29) |
| `GET /customer/history` | الزيارات والخدمات وحالة الدفع |
| `POST /devices` | `{fcmToken, notificationsAllowed, hasPlayServices}` |

## الطاقم (الحلاق)
| الطلب | الوصف |
|---|---|
| `GET /staff/today` | طابوري + الخدمات والأسعار + الاستراحات + الإعدادات + `serverTime` + `seq` |
| `POST /sync/events` | دفعة أحداث (أدناه) ← لكل حدث `applied` / `duplicate` / `rejected` + السبب |
| `GET /sync?since={seq}` | التغييرات منذ الرقم ← `{changes[], seq, serverTime}` |
| `POST /heartbeat` | `{deviceSeq, queueDigest?}` كل 30 ث — `queueDigest` اختياري ويتجاهله السيرفر حاليًا (محجوز لمقارنة الطابور لاحقًا) |
| `POST /staff/walk-ins` | `{name, phone, serviceIds[]}` — متصل فقط؛ آخر طابور الحلاق؛ خلال الدوام الجاري فقط (بعد الإغلاق `409 NOT_WORKING_NOW`) |
| `POST /staff/impact` | `{bookingId, serviceIds[]}` ← معاينة الأثر (ق9، ق24) |
| `GET /staff/payments` | بانتظار التأكيد / مؤكدة |
| `WS /staff/stream` | يدفع التغييرات بأرقامها لحظيًا |

### أشكال مثبّتة (المعلم 4ب)
- **الحجز** (`Booking`): `{id, customerId, barberId, serviceIds[], kind, requestedAt?, status, queuePosition?, originalEta, lastShownEta?, postponementUsed, actualStart?, actualEnd?, source: app|barber, walkIn, createdAt}` مع حقول إضافية: `workDate, customerName, services[{id,name,priceCents,baseDurationMin}], priceCents, estimatedDurationMin, eta, etaEnd, calledAt, offerExpiresAt, lastChangeReason, serveLate, needsReview` (+ `customerPhone` في قوائم الطاقم). الحالة `expired` (عرض منتهٍ) لا تظهر في القوائم.
- **يوم العمل التشغيلي (C1):** `GET /staff/today` و`POST /heartbeat` و`GET /manager/queues` والمؤقتات تعمل على الدوام الجاري، أو — بعد الإغلاق — على آخر يوم ما زال فيه حجز نشط (`in_service` / `waiting` / `called`، مثل «خدمة بعد الإغلاق» ق24) حتى يبدأ اليوم التالي (فتح حجزه) **أو تنقضي مهلة ما بعد الإغلاق — أيهما أسبق** (الجولة 2: `dayCloseGraceMinutes`، الافتراضي 360 دقيقة بعد نهاية دوام ذلك اليوم؛ فلا يبقى يوم قديم «تشغيليًا» أيامًا عند صالون يغلق الجمعة أو حلاق يعمل يومًا واحدًا في الأسبوع)، ثم على اليوم التالي. لا يُقبل بعد الإغلاق حجز جديد ولا زبون حاضر. عند بدء اليوم التالي أو انقضاء المهلة يُغلق السيرفر اليوم السابق (ولا يُستدعى أحد منه ولا يُنبَّه بعدها): `waiting`/`called` ← `cancelled` بسبب `day_closed` (`cancel_reason = "day_closed"`، تنبيه `cancelled_closing` مع `data.reason = "day_closed"`)، و`in_service` يبقى ليُنهيه الحلاق مع `needsReview: true` وتعارض للمدير (`unfinished_at_day_close`) — انظر «الخدمات المعلّقة من يوم مُغلق» أدناه؛ ولا يظهر أيٌّ منها في `GET /bookings/current` ولا يُحتسب ضمن الحجوزات النشطة.
- `GET /staff/today` ← `{day: {workDate, workStart, workEnd, state, firstConnectedAt} | null, queue[Booking], services[], breaks[{id, kind: rest|prayer|emergency, start, end, open}], walkInOnly[{id, start, end}], closingWarnings[bookingId], unfinishedFromPreviousDay[Booking + customerPhone], settings{callAheadMinutes, etaChangeNotifyMinutes, overrunAlertPercent, dayCloseGraceMinutes, …}, serverTime, seq}`. `unfinishedFromPreviousDay` (الجولة 2) موجود دائمًا (مصفوفة، قد تكون فارغة، حتى مع `day: null`).
- **الخدمات المعلّقة من يوم مُغلق (الجولة 2):** حجز كان `in_service` حين أُغلق يومه يبقى `in_service` مع `needsReview: true` و`workDate` يومه الأصلي. يظهر للحلاق في `GET /staff/today` ← `unfinishedFromPreviousDay`، وللمدير في `GET /manager/queues` (لكل حلاق وإجماليًا) وفي `pendingItems.unfinishedServices`. يُنهيه الحلاق بحدث `service_finished` عاديًا ثم `payment_confirmed` (عينة مدته مستبعدة من التعلم `after_day_close`، ويُعلَّم التعارض محلولًا)، أو يحسمه المدير عبر `POST /manager/bookings/{id}/resolve` (أدناه).
- `POST /sync/events` بجسم `{events: [...]}` (حتى 200) ← مصفوفة `[{eventId, result: applied|duplicate|rejected, reason?}]` بترتيب الإرسال.
- `GET /sync?since=` ← `{changes: [SyncChange], seq, hasMore, serverTime}`، و**`SyncChange` = `{seq, type, bookingId?, data, occurredAt}`**. الأنواع: `booking_created`، `booking_offered`، `booking_updated`، `booking_called`، `booking_removed` (`data` = الحجز)، `queue_updated` (`data = {workDate, reason, queue[{bookingId, status, position, eta, etaEnd}]}`)، `payment_updated` (`data = {bookingId, status, amountCents (المتوقع = سعر السيرفر), confirmedAmountCents?, discrepancy?}`)، `break_started`/`break_ended` (`break_ended` قد يحمل `automatic: true` حين يُغلق السيرفر استراحة مفتوحة بعد انتهاء اليوم)، `breaks_changed` (`data = {workDate}` — أضاف المدير استراحة أو حذفها؛ أعد جلب `GET /staff/today`)، `day_state` (يشمل غياب اليوم الذي يسجّله المدير أو يلغيه). التغييرات التي تكتبها وحدات أخرى دون نوع تصل بنوع `{entity}_{op}`.
- `POST /heartbeat` ← `{serverTime, seq, workDate, state, reconnected}` (`workDate` يوم العمل التشغيلي، انظر أعلاه).
- `WS /v1/staff/stream` (L6): المصادقة برمز الوصول نفسه — **لا يُقبل الرمز في عنوان الطلب** (`?access_token=` يُتجاهل). إحدى ثلاث طرق: ترويسة `Authorization: Bearer …`، أو بروتوكولان فرعيان `Sec-WebSocket-Protocol: saloni.v1, bearer.<الرمز>` (يرد السيرفر بـ`saloni.v1` ولا يعيد الرمز)، أو اتصال بلا رمز ثم أول رسالة `{"type": "auth", "token": "…"}` خلال 10 ث. الرسائل `{type: "hello", seq, serverTime}` ثم `{type: "changes", seq}`. الإغلاق: 4401 (رمز منتهٍ، جلسة أُلغيت، مصادقة فاشلة أو متأخرة)، 4403 (ليس طاقمًا)، 4408 (أكثر من 3 اتصالات للحساب نفسه — يُغلق الأقدم). يُعاد التحقق من الجلسات كل دقيقة.
- `GET /bookings/current` ← كما أعلاه + `etaEnd, lastChangeReasonCode, dayState, barber{id,name}, serverTime`؛ إن لم يوجد حجز نشط: **`200 {"booking": null, "serverTime"}`** (لا `404`).
- `GET /customer/today` ← `{serverTime, accountStatus: pending|active, currency, services[{id, name, baseDurationMin, priceCents, active}], barbers[{id, name, photoUrl (null حاليًا), dayState: not_connected_yet|connected|disconnected|absent_today, nextAvailableStart | null, queueLength, accepting, workStart | null, workEnd | null}]}`. `nextAvailableStart` = أقرب بدء لأقصر خدمة وفق ق4؛ الحلاق بلا دوام اليوم يظهر بـ`accepting: false` وأوقات `null`.
- `GET /customer/history` ← مصفوفة (الأحدث أولًا، حتى 100) من `Booking` + `{barberName, payment: {status: awaiting_confirmation|confirmed, amountCents} | null}`؛ تشمل سجل الحاضر المربوط بالحساب (ق20)، ولا تشمل `offered`/`expired`.
- `POST /bookings` بساعة غير متاحة: `409 SLOT_UNAVAILABLE` مع `error.details = {nearest (ISO), barberId}` (لا يُحجز شيء؛ للعرض المحجوز مؤقتًا استخدم `quote`).
- `POST /bookings/{id}/change-time` عند تعذّر الساعة: `409 SLOT_UNAVAILABLE` ويبقى الحجز كما هو، و`error.details.offer` عرض (بصيغة `quote`) محجوز مؤقتًا؛ قبوله `POST /bookings {offerId}` ينقل الحجز نفسه.
- `POST /staff/impact` ← `{bookingId, oldDurationMin, newDurationMin, oldPriceCents, newPriceCents, changes[{bookingId, customerName, before, after, deltaMin, pastClosing, notify}], pastClosing[{bookingId, customerName, end, newlyPastClosing}], workEnd}`.
- `GET /staff/payments` ← `[{id, bookingId, amountCents, confirmedAmountCents, discrepancy, status, confirmedBy, confirmedAt, barberId, customerName, workDate, finishedAt, createdAt}]` — `amountCents` هو المبلغ المتوقع (لقطة أسعار السيرفر ولا يغيّره الجهاز)، و`confirmedAmountCents` ما أبلغ به الجهاز عند التأكيد (`null` قبله)، و`discrepancy` إن اختلفا.

### أحداث الجهاز
كل حدث: `{id (UUID), deviceSeq, type, bookingId?, occurredAt, approximate, payload}`.
- **التحقق المسبق (M4):** النوع والحمولة و`bookingId` ووقت الحدوث تُفحص قبل أي عمل على القاعدة؛ المرفوض هنا (`UNKNOWN_EVENT_TYPE` / `INVALID_PAYLOAD` / `BOOKING_REQUIRED` / `INVALID_TIME`) يُسجَّل دفعة واحدة (فيعود `duplicate` عند إعادة الإرسال) بسجل تعارض واحد للدفعة. تعارضات آلة الحالات حدها 10 سجلات لكل دفعة ثم سجل ملخّص. حد المعدل: 60 دفعة في الدقيقة لكل حساب طاقم (`429`).
- **تصحيح الأوقات (L1):** `occurredAt` لا يسبق إنشاء الحجز (للبدء) ولا بدء الخدمة (للإنهاء) ولا يتجاوز الآن بأكثر من دقيقتين؛ ما خرج عن ذلك يُصحَّح إلى الحد ويُعامل «تقريبيًا» وتُستبعد عينة مدته (`clamped_time`).
- `payment_confirmed`: المبلغ المتوقع يبقى سعر السيرفر؛ يُسجَّل `amount` المرسل مبلغًا مؤكدًا، وإن اختلف تعود النتيجة `applied` مع `reason: "AMOUNT_DIFFERS_FROM_PRICE"` ويُعلَّم الفرق للمدير.

| النوع | الحمولة |
|---|---|
| `service_started` | — |
| `service_finished` | — |
| `services_changed` | `{serviceIds[]}` |
| `payment_confirmed` | `{amount}` |
| `postponed` | `{steps}` |
| `waited` | — |
| `no_show` | — |
| `closing_decision` | `{decision: serve_late\|cancel, reason}` |
| `break_started` / `break_ended` | `{kind: rest\|prayer\|emergency}` |
| `absent_today` | `{reason}` |

## المدير
| المورد | الطلبات |
|---|---|
| ملف الصالون | `GET /manager/profile`، `PUT /manager/profile` (تحديث جزئي: `{name?, about?, address?, location?: {lat, lng} \| null, phone?, whatsapp?, socialLinks?[{platform, url}]}`) — روابط التواصل `https://` فقط (L3) |
| الصور (حتى 6) | `POST /manager/photos` ← `201 {id, path, url, position}`؛ `DELETE /manager/photos/{id}` ← `{ok: true}`؛ `409 PHOTOS_LIMIT_REACHED` |
| الشعار | `POST /manager/profile/logo` ← `201 {logo (رابط), path}`؛ `DELETE /manager/profile/logo` ← `{ok: true}` |
| الكتالوج | `GET/POST /manager/catalog`، `PUT/DELETE /manager/catalog/{id}`، `POST/DELETE /manager/catalog/{id}/photo` |
| الخدمات | `GET/POST /manager/services`، `PUT/DELETE /manager/services/{id}` (`409 SERVICE_IN_USE` عند الحذف إن كانت مستخدمة). الحدود (L8): السعر ≤ 100000000 (بأصغر وحدة)، المدة 1–480 د، الترتيب ≤ 10000 — والسعر نفسه في الكتالوج |
| الطاقم | `GET/POST /manager/staff`، `PUT /manager/staff/{id}`، `POST /manager/staff/{id}/reset-code`. عنصر القائمة يضيف `is_owner` و`suspended_at` (ق40: وقت آخر إيقاف، `null` للنشط؛ يُسجَّل عند `active: false` ويُفرَّغ عند إعادة التفعيل). المالك لا يُخفَّض ولا يوقَف (`409 OWNER_PROTECTED`)، ويبقى للصالون مدير نشط واحد على الأقل (`409 LAST_MANAGER`) — L5 |
| الدوام الأسبوعي | `GET /manager/schedules` ← `[{staffId \| null, weekday (0=الأحد), opensAt "HH:MM", closesAt}]`؛ `PUT /manager/schedules` بجسم `{staffId \| null, weekday, opensAt, closesAt}` (إدراج أو تحديث؛ `null` = افتراضي الصالون لذلك اليوم؛ إغلاق قبل الفتح = يعبر منتصف الليل)؛ `DELETE /manager/schedules/{weekday}?staffId=` (بلا `staffId` = حذف الافتراضي) ← `{ok: true}` |
| الاستراحات وفترات الحاضرين (ق33) | `GET /manager/breaks`؛ `POST /manager/breaks` بجسم `{staffId \| "all", type: rest\|prayer\|emergency\|walk_in_only, startTime, endTime}` (يومية) أو `{…, workDate, startsAt, endsAt}` (مؤرخة) ← مصفوفة المنشأ؛ `409 BREAK_OVERLAP`؛ `DELETE /manager/breaks/{id}` ← `{ok: true}`. `workDate` بصيغة `YYYY-MM-DD`. تُنفَّذ داخل قفل يوم الحلاق: يُعاد حساب طابوره بسبب `schedule_changed` (وتنطبق ق5) ويصل أجهزته `breaks_changed` (I6) |
| الإجازات (غائب اليوم) | `GET /manager/absences`؛ `POST /manager/absences` بجسم `{staffId, workDate, reason?}`؛ `DELETE /manager/absences/{id}` ← `{ok: true}` — داخل قفل اليوم، مع `day_state` لأجهزة الحلاق (I6) |
| الإعدادات | `GET/PUT /manager/settings` — تشمل `dayCloseGraceMinutes` (الجولة 2؛ 60–720، الافتراضي 360): أقصى مدة يبقى فيها يوم انتهى دوامه «تشغيليًا» (خدمة بعد الإغلاق ق24) قبل أن يُغلق |
| الزبائن | `GET /manager/customers?status=pending\|active\|suspended&limit=&offset=` (العنصر يضيف `proposed_walk_in_id`, `phone_released_at`)، `POST /manager/customers/{id}/approve\|suspend\|reset-code`، `POST /manager/customers/{id}/link-walkin` بجسم `{walkInId}`؛ وجديد (H2، كلها مسجّلة في التدقيق): `POST /manager/customers/{id}/unlink-walkin` ← `{ok: true}` (يفك الربط أو الاقتراح)، `PUT /manager/customers/{id}/phone` بجسم `{phone}` ← الزبون (إعادة إسناد رقم؛ تُلغى جلساته والربط؛ `409 PHONE_IN_USE`)، `POST /manager/customers/{id}/release-phone` ← `{ok: true}` (يوقف الحساب ويُفرج عن رقمه ليسجّل به صاحبه الحقيقي؛ لا يُعتمد بعدها قبل إسناد رقم: `409 PHONE_RELEASED`) |
| ربط سجل الحاضر (ق20، H2) | عند التسجيل برقم له سجل حاضر (والاعتماد مفعّل) يُحفظ **ربط مقترح** فقط (`proposed_walk_in_id`) ولا يصبح فعّالًا إلا حين يعتمد المدير الحساب. لا يظهر سجل الحاضر المربوط في `GET /customer/history` إلا لحساب **نشط**. الزبون الحاضر الجديد لا يُربط تلقائيًا إلا بحساب نشط |
| نزاعات الأرقام (ق20) | `GET /manager/phone-disputes` ← `[{phone, accountId \| null, accountStatus \| null, linkedWalkInId \| null, proposedWalkInId \| null, walkIns[{id, name, createdAt}]}]` — رقم له سجلّا حاضر أو أكثر غير مربوطين، **أو** حساب معلّق/موقوف يحمل رقمًا له سجلات حاضر؛ `POST /manager/phone-disputes/{accountId}/resolve` بجسم `{walkInId}` ← `{ok: true}` (`409 WALK_IN_ALREADY_LINKED` / `PHONE_MISMATCH`) |
| الطوابير | `GET /manager/queues`، `POST /manager/bookings/{id}/transfer` (ق25)، `POST /manager/bookings/{id}/resolve` (الجولة 2) — الأشكال أدناه |
| إجراءات حساب موقوف (ق40) | `POST /manager/staff/{id}/recover-events`، `GET /manager/recovered-events?status=pending\|all`، `POST /manager/recovered-events/{id}/ack` — الأشكال أدناه |
| التقارير | `GET /manager/reports?from=&to=` (§9). الإيرادات لكل حلاق وللإجمالي: `{confirmed (المحصّل فعلًا كما أكده الجهاز), expectedConfirmed (سعر السيرفر للمؤكد), awaiting, discrepancies}`؛ إيراد `topServices` من الدفعات المؤكدة (موزّعًا على خدمات الحجز بنسبة أسعارها)؛ `durationVsBase` يستبعد الأوقات التقريبية والمصحّحة؛ `pendingItems` يضيف `paymentDiscrepancies`، و`phoneDisputes` بتعريف شاشة النزاعات نفسه، و`unfinishedServices` (الجولة 2: عدد الخدمات المعلّقة من يوم مُغلق)، و`recoveredEvents` (ق40: إجراءات مستردة لم تُراجع — وهي ضمن `syncConflicts` أيضًا) |

**رفع الصور:** للصالونات **المفعّلة** فقط (`409 SALON_NOT_ACTIVE` قبل التفعيل — H3). `multipart/form-data` بحقل ملف واحد اسمه **`file`** (للصور والشعار وصورة الكتالوج). JPEG/PNG/WebP فقط (يُفحص المحتوى الفعلي)، حد الحجم في الخادم، ويُعاد الترميز وتُزال بيانات EXIF. الأخطاء: `400 VALIDATION_FAILED` (ملف مفقود أو غير صورة)، `413` (كبير جدًا).

### أشكال مثبّتة — المدير
- `GET /manager/profile` ← `{code, name, about, logo (رابط أو null), photos[{id, url, position}], address, location {lat, lng} | null, phone, whatsapp, socialLinks[{platform, url}], updatedAt}`. الروابط بصيغة الملف العام نفسها `/v1/media/{code}/{file}` (تُخدم بعد تفعيل الصالون). `PUT` يعيد الشكل نفسه.
- `GET /manager/queues` ← `{serverTime, seq, barbers[{id, name, role, day: {workDate, workStart, workEnd, state, firstConnectedAt} | null, accepting, queue[Booking + customerPhone], unfinishedFromPreviousDay[Booking + customerPhone]}], unfinishedFromPreviousDay[Booking + customerPhone]}` — كل الطاقم الذين لهم دوام؛ `unfinishedFromPreviousDay` (الجولة 2) لكل حلاق، والمصفوفة العليا تجمعها كلها (بما فيها لطاقم لم يعد له دوام)؛ الطابور بترتيب الخدمة (in_service ثم called ثم waiting) مع `eta/etaEnd` المحسوبة الآن؛ العروض المؤقتة (`offered`) لا تظهر.
- `POST /manager/bookings/{id}/transfer` بجسم `{toBarberId}` وترويسة `Idempotency-Key` ← `200 Booking` (عند الحلاق الجديد، مع `customerPhone`). للمدير فقط. يُقبل للحالات `waiting` و`called` فقط (`called` يعود `waiting` ويُستدعى من جديد عند الحلاق الجديد). يُدرج وفق ق4/ق19 عند الحلاق الجديد (لا يتأخر أحد) ويحافظ على `originalEta`؛ يُسجَّل حدث `transferred` (السبب `transferred`) وسجل تدقيق `booking.transferred`، ويصل الزبونَ تنبيه `transferred`، ويصبح الوقت الجديد مرجع ق5. من تقدّم عند الحلاق السابق يُسجَّل تغيّر وقته بالسبب `transferred_ahead` (وتنطبق عليه ق5). تغييرات المزامنة: `booking_removed` للحلاق السابق و`booking_created` للجديد. الأخطاء: `404 BOOKING_NOT_FOUND` / `BARBER_NOT_FOUND`، `409 TRANSFER_SAME_BARBER` / `BOOKING_STARTED` / `BOOKING_NOT_ACTIVE` / `BARBER_NOT_WORKING` / `BARBER_ABSENT` / `BARBER_UNAVAILABLE`، و**`409 TRANSFER_NO_SLOT`** إن لم يتسع يوم الحلاق المختار مع `error.details = {nearest: {barberId, barberName, start, end} | null, alternatives[نفس الشكل، الأقرب أولًا]}` (حلاقون آخرون يتسع عندهم الآن؛ للاسترشاد فقط، لا يُحجز شيء).

- `POST /manager/bookings/{id}/resolve` (الجولة 2، للمدير فقط، ترويسة `Idempotency-Key` اختيارية) لحسم خدمة معلّقة من يوم مُغلق: `{action: "finish", actualEnd (ISO)}` ← يُنهيها بوقت الانتهاء الفعلي (لا قبل بدء الخدمة ولا بعد الآن)، ويُنشأ دفع بانتظار التأكيد بسعر السيرفر (يؤكده الحلاق أو المدير بـ`payment_confirmed`)، ولا يُتعلَّم من مدتها؛ أو `{action: "cancel", reason (1–200)}` ← `cancelled` مع `cancel_reason = "manager: {reason}"`. يعيد `200 Booking` (+ `customerPhone`). يُسجَّل حدث (`service_finished` أو `cancelled` بالسبب `manager_resolved`) وتدقيق `booking.unfinished_resolved`، ويُعلَّم التعارض `unfinished_at_day_close` محلولًا، ويصل جهاز الحلاق `booking_updated` (+ `payment_updated`) أو `booking_removed`. الأخطاء: `404 BOOKING_NOT_FOUND`، `409 BOOKING_NOT_UNFINISHED` (ليس `in_service` من يوم مُغلق)، `400 INVALID_END_TIME`، `400 VALIDATION_FAILED`.

### ق40 — إجراءات حساب موقوف (للمدير فقط؛ الصالون من رمز الجلسة)
- `POST /manager/staff/{id}/recover-events` بجسم `POST /sync/events` نفسه `{events: [...]}` (حتى 200 حدث؛ الأكثر يُقسَّم) ← `200 {staffId, suspendedAt, results: [{eventId, result: applied|duplicate|rejected_after_suspension|rejected_invalid, reason?}] (بترتيب الإرسال), summary: {applied, duplicate, rejectedAfterSuspension, rejectedInvalid}}`. يرفعه المدير من جهاز الحساب الموقوف: الأحداث تُنسب لذلك الحساب وتمر بالتحقق المسبق وآلة الحالات نفسيهما، ومرة واحدة لكل `id` (إعادة الرفع ← `duplicate`، أو النتيجة نفسها لما رُفض). **يُطبّق فقط ما `occurredAt` (المصحّح) فيه قبل `suspendedAt` تمامًا** وليس أقدم منه بأكثر من 48 ساعة؛ ما عدا ذلك `rejected_after_suspension` (`reason: "AFTER_SUSPENSION"`) أو `rejected_invalid` (`EVENT_TOO_OLD`، `NOT_YOUR_BOOKING`، `UNKNOWN_EVENT_TYPE`، …) ولا يُطبّق. المطبَّق يُعلَّم `flagged` و`recovered_by_staff_id` (في `device_events` و`booking_events`) ويُدرج في قائمة المراجعة؛ ويُكتب تدقيق `staff.events_recovered` لكل رفع. حد المعدل كدفعات المزامنة (لكل مدير). الأخطاء: `403` لغير المدير، `404 NOT_FOUND` (معرّف غير موجود في هذا الصالون)، `409 ACCOUNT_NOT_SUSPENDED`، `400 VALIDATION_FAILED`.
- `GET /manager/recovered-events?status=pending|all` (الافتراضي `pending`؛ الأحدث أولًا، حتى 500) ← `[{id, staffId, staffName, eventId, type, bookingId, customerName, occurredAt, approximate, suspendedAt, reason, recoveredBy: {id, name} | null, recoveredAt, reviewedAt, reviewedBy: {id, name} | null}]`.
- `POST /manager/recovered-events/{id}/ack` ← `{ok: true}` (تكراره آمن؛ تدقيق `staff.recovered_event_reviewed`)؛ `404` لعنصر غير موجود أو ليس إجراءً مستردًا.

## التنبيهات (FCM)
`{type, bookingId, title, body}` — الأنواع: `booking_confirmed`، `called`، `eta_changed`، `postponed`، `no_show`، `cancelled_closing`، `transferred`، `overrun` (للحلاق)، `account_pending`، `barber_not_connected`، `barber_absent`، `sync_conflict`، `base_duration_suspect` (للمدير). قيم `data` نصية. النصوص كما في التصميم §8.
- `transferred` (للزبون): «نُقل حجزك إلى {الحلاق} — الوقت المتوقع {الوقت}»؛ `data` تضيف `eta` و`barberId`.
- `base_duration_suspect` (للمدير، §5.10): حين يُستبعد نصف آخر 10 عينات أو أكثر (5 على الأقل) لحلاق ومجموعة خدمات مقارنةً بالمدة الأساسية — «مدد «{الخدمات}» الفعلية لدى {الحلاق} تختلف كثيرًا عن المدة الأساسية ({س} د) — راجعها من شاشة الخدمات». مرة واحدة لكل مجموعة خدمات في يوم العمل. `data` = `{serviceSetKey, barberId, baseDurationMin}` (بلا `bookingId`).

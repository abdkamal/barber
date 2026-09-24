# عقد الواجهة البرمجية (v1)

مرجع مشترك للسيرفر وتطبيقي Flutter. مشتق من `design.md` (2.1). الأوقات بصيغة ISO-8601 UTC، والمبالغ أعداد صحيحة بأصغر وحدة للعملة (هللة)، والعملة من ملف الصالون.

## قواعد عامة
- كل الطلبات عبر HTTPS تحت `/v1`. الصالون يُستخرج من رمز الجلسة فقط، لا من الطلب (§7).
- الأخطاء: `{"error": {"code": "SLOT_UNAVAILABLE", "message": "نص عربي للعرض", "details"?: …}}` مع حالة HTTP مناسبة. `details` اختياري ويظهر فقط حيث يُذكر أدناه:
  `VALIDATION_FAILED` ← `details = [{path, code, …}]`؛ `SLOT_UNAVAILABLE` من `POST /bookings` ← `details = {nearest, barberId}`، ومن `change-time` ← `details = {offer}`؛ `TRANSFER_NO_SLOT` ← `details = {nearest, alternatives[]}`. التكرار بمفتاح `Idempotency-Key` يعيد `details` كما هو.
- رموز أخطاء الحجز الشائعة: `ACCOUNT_PENDING` (403 — حساب الزبون بانتظار اعتماد الصالون؛ على `quote` و`bookings` و`change-time`)، `ACCOUNT_SUSPENDED` (403 — عند الدخول/التجديد؛ الحساب الموقوف تُلغى جلساته فيصله `401`)، `SERVICE_UNAVAILABLE` (400)، `BARBER_NOT_FOUND` / `BOOKING_NOT_FOUND` / `OFFER_NOT_FOUND` (404)، `BOOKING_CLOSED` / `OUTSIDE_WORKING_HOURS` / `BARBER_ABSENT` / `BARBER_UNAVAILABLE` / `NO_SLOT` / `MAX_ACTIVE_BOOKINGS` / `SLOT_UNAVAILABLE` / `BOOKING_STARTED` / `BOOKING_NOT_ACTIVE` / `BOOKING_CALLED` / `PAST_CLOSING` / `NOT_WORKING_NOW` (409)، `OFFER_EXPIRED` (410)، `IDEMPOTENCY_KEY_REUSED` (422).
- الطلبات التي تنشئ أو تغيّر حجزًا أو دفعًا تحمل ترويسة `Idempotency-Key` (UUID)؛ تكرارها يعيد النتيجة الأولى.
- حدود المعدل تعيد `429` مع `Retry-After`.

## عام (بلا دخول)
| الطلب | الوصف |
|---|---|
| `GET /salons/{code}` | ملف الصالون العام (للصالونات المفعّلة فقط): الاسم، الشعار، النبذة، العنوان، الإحداثيات، وسائل الاتصال، الصور، ساعات العمل، الكتالوج. روابط الصور والشعار بصيغة `/v1/media/{code}/{file}` |
| `GET /media/{code}/{file}` | ملف صورة مخزّن (صور الصالون، الشعار، صور الكتالوج) — للصالونات المفعّلة فقط، وإلا `404`؛ `Cache-Control: public, max-age=86400, immutable` |
| `POST /salons/register` | تسجيل صاحب صالون (ق37) ← صالون `pending_activation` + حساب مدير |

## الدخول
| الطلب | الوصف |
|---|---|
| `POST /auth/customer/register` | `{salonCode, name, phone, password}` ← حساب (`pending` إن كان الاعتماد مطلوبًا) + جلسة |
| `POST /auth/customer/login` | `{salonCode, phone, password}` |
| `POST /auth/staff/login` | `{salonCode, username, password}` |
| `POST /auth/refresh` | `{refreshToken}` ← زوج جديد (تدوير؛ إعادة الاستخدام تلغي العائلة) |
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
| `POST /bookings/{id}/seen` | `{eta}` — ما عرضه التطبيق فعلًا؛ مرجع التنبيه الإلزامي (ق5) |
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
| `POST /staff/walk-ins` | `{name, phone, serviceIds[]}` — متصل فقط؛ آخر طابور الحلاق |
| `POST /staff/impact` | `{bookingId, serviceIds[]}` ← معاينة الأثر (ق9، ق24) |
| `GET /staff/payments` | بانتظار التأكيد / مؤكدة |
| `WS /staff/stream` | يدفع التغييرات بأرقامها لحظيًا |

### أشكال مثبّتة (المعلم 4ب)
- **الحجز** (`Booking`): `{id, customerId, barberId, serviceIds[], kind, requestedAt?, status, queuePosition?, originalEta, lastShownEta?, postponementUsed, actualStart?, actualEnd?, source: app|barber, walkIn, createdAt}` مع حقول إضافية: `workDate, customerName, services[{id,name,priceCents,baseDurationMin}], priceCents, estimatedDurationMin, eta, etaEnd, calledAt, offerExpiresAt, lastChangeReason, serveLate, needsReview` (+ `customerPhone` في قوائم الطاقم). الحالة `expired` (عرض منتهٍ) لا تظهر في القوائم.
- `GET /staff/today` ← `{day: {workDate, workStart, workEnd, state, firstConnectedAt} | null, queue[Booking], services[], breaks[{id, kind: rest|prayer|emergency, start, end, open}], walkInOnly[{id, start, end}], closingWarnings[bookingId], settings{callAheadMinutes, etaChangeNotifyMinutes, overrunAlertPercent, …}, serverTime, seq}`.
- `POST /sync/events` بجسم `{events: [...]}` (حتى 200) ← مصفوفة `[{eventId, result: applied|duplicate|rejected, reason?}]` بترتيب الإرسال.
- `GET /sync?since=` ← `{changes: [SyncChange], seq, hasMore, serverTime}`، و**`SyncChange` = `{seq, type, bookingId?, data, occurredAt}`**. الأنواع: `booking_created`، `booking_offered`، `booking_updated`، `booking_called`، `booking_removed` (`data` = الحجز)، `queue_updated` (`data = {workDate, reason, queue[{bookingId, status, position, eta, etaEnd}]}`)، `payment_updated`، `break_started`/`break_ended`، `day_state`. التغييرات التي تكتبها وحدات أخرى دون نوع تصل بنوع `{entity}_{op}`.
- `POST /heartbeat` ← `{serverTime, seq, workDate, state, reconnected}`.
- `WS /v1/staff/stream`: المصادقة برمز الوصول نفسه (ترويسة `Authorization` أو `?access_token=`)؛ الرسائل `{type: "hello", seq, serverTime}` ثم `{type: "changes", seq}`؛ يُغلق الاتصال (4401) عند انتهاء الرمز أو إلغاء الجلسة.
- `GET /bookings/current` ← كما أعلاه + `etaEnd, lastChangeReasonCode, dayState, barber{id,name}, serverTime`؛ إن لم يوجد حجز نشط: **`200 {"booking": null, "serverTime"}`** (لا `404`).
- `GET /customer/today` ← `{serverTime, accountStatus: pending|active, currency, services[{id, name, baseDurationMin, priceCents, active}], barbers[{id, name, photoUrl (null حاليًا), dayState: not_connected_yet|connected|disconnected|absent_today, nextAvailableStart | null, queueLength, accepting, workStart | null, workEnd | null}]}`. `nextAvailableStart` = أقرب بدء لأقصر خدمة وفق ق4؛ الحلاق بلا دوام اليوم يظهر بـ`accepting: false` وأوقات `null`.
- `GET /customer/history` ← مصفوفة (الأحدث أولًا، حتى 100) من `Booking` + `{barberName, payment: {status: awaiting_confirmation|confirmed, amountCents} | null}`؛ تشمل سجل الحاضر المربوط بالحساب (ق20)، ولا تشمل `offered`/`expired`.
- `POST /bookings` بساعة غير متاحة: `409 SLOT_UNAVAILABLE` مع `error.details = {nearest (ISO), barberId}` (لا يُحجز شيء؛ للعرض المحجوز مؤقتًا استخدم `quote`).
- `POST /bookings/{id}/change-time` عند تعذّر الساعة: `409 SLOT_UNAVAILABLE` ويبقى الحجز كما هو، و`error.details.offer` عرض (بصيغة `quote`) محجوز مؤقتًا؛ قبوله `POST /bookings {offerId}` ينقل الحجز نفسه.
- `POST /staff/impact` ← `{bookingId, oldDurationMin, newDurationMin, oldPriceCents, newPriceCents, changes[{bookingId, customerName, before, after, deltaMin, pastClosing, notify}], pastClosing[{bookingId, customerName, end, newlyPastClosing}], workEnd}`.
- `GET /staff/payments` ← `[{id, bookingId, amountCents, status, confirmedBy, confirmedAt, barberId, customerName, workDate, finishedAt, createdAt}]`.

### أحداث الجهاز
كل حدث: `{id (UUID), deviceSeq, type, bookingId?, occurredAt, approximate, payload}`.

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
| ملف الصالون | `GET /manager/profile`، `PUT /manager/profile` (تحديث جزئي: `{name?, about?, address?, location?: {lat, lng} \| null, phone?, whatsapp?, socialLinks?[{platform, url}]}`) |
| الصور (حتى 6) | `POST /manager/photos` ← `201 {id, path, url, position}`؛ `DELETE /manager/photos/{id}` ← `{ok: true}`؛ `409 PHOTOS_LIMIT_REACHED` |
| الشعار | `POST /manager/profile/logo` ← `201 {logo (رابط), path}`؛ `DELETE /manager/profile/logo` ← `{ok: true}` |
| الكتالوج | `GET/POST /manager/catalog`، `PUT/DELETE /manager/catalog/{id}`، `POST/DELETE /manager/catalog/{id}/photo` |
| الخدمات | `GET/POST /manager/services`، `PUT/DELETE /manager/services/{id}` (`409 SERVICE_IN_USE` عند الحذف إن كانت مستخدمة) |
| الطاقم | `GET/POST /manager/staff`، `PUT /manager/staff/{id}`، `POST /manager/staff/{id}/reset-code` |
| الدوام الأسبوعي | `GET /manager/schedules` ← `[{staffId \| null, weekday (0=الأحد), opensAt "HH:MM", closesAt}]`؛ `PUT /manager/schedules` بجسم `{staffId \| null, weekday, opensAt, closesAt}` (إدراج أو تحديث؛ `null` = افتراضي الصالون لذلك اليوم؛ إغلاق قبل الفتح = يعبر منتصف الليل)؛ `DELETE /manager/schedules/{weekday}?staffId=` (بلا `staffId` = حذف الافتراضي) ← `{ok: true}` |
| الاستراحات وفترات الحاضرين (ق33) | `GET /manager/breaks`؛ `POST /manager/breaks` بجسم `{staffId \| "all", type: rest\|prayer\|emergency\|walk_in_only, startTime, endTime}` (يومية) أو `{…, workDate, startsAt, endsAt}` (مؤرخة) ← مصفوفة المنشأ؛ `409 BREAK_OVERLAP`؛ `DELETE /manager/breaks/{id}` ← `{ok: true}` |
| الإجازات (غائب اليوم) | `GET /manager/absences`؛ `POST /manager/absences` بجسم `{staffId, workDate, reason?}`؛ `DELETE /manager/absences/{id}` ← `{ok: true}` |
| الإعدادات | `GET/PUT /manager/settings` |
| الزبائن | `GET /manager/customers?status=pending\|active\|suspended&limit=&offset=`، `POST /manager/customers/{id}/approve\|suspend\|reset-code`، `POST /manager/customers/{id}/link-walkin` بجسم `{walkInId}` |
| نزاعات الأرقام (ق20) | `GET /manager/phone-disputes` ← `[{phone, accountId \| null, walkIns[{id, name, createdAt}]}]`؛ `POST /manager/phone-disputes/{accountId}/resolve` بجسم `{walkInId}` ← `{ok: true}` (`409 WALK_IN_ALREADY_LINKED` / `PHONE_MISMATCH`) |
| الطوابير | `GET /manager/queues`، `POST /manager/bookings/{id}/transfer` (ق25) — الأشكال أدناه |
| التقارير | `GET /manager/reports?from=&to=` (§9) |

**رفع الصور:** `multipart/form-data` بحقل ملف واحد اسمه **`file`** (للصور والشعار وصورة الكتالوج). JPEG/PNG/WebP فقط (يُفحص المحتوى الفعلي)، حد الحجم في الخادم، ويُعاد الترميز وتُزال بيانات EXIF. الأخطاء: `400 VALIDATION_FAILED` (ملف مفقود أو غير صورة)، `413` (كبير جدًا).

### أشكال مثبّتة — المدير
- `GET /manager/profile` ← `{code, name, about, logo (رابط أو null), photos[{id, url, position}], address, location {lat, lng} | null, phone, whatsapp, socialLinks[{platform, url}], updatedAt}`. الروابط بصيغة الملف العام نفسها `/v1/media/{code}/{file}` (تُخدم بعد تفعيل الصالون). `PUT` يعيد الشكل نفسه.
- `GET /manager/queues` ← `{serverTime, seq, barbers[{id, name, role, day: {workDate, workStart, workEnd, state, firstConnectedAt} | null, accepting, queue[Booking + customerPhone]}]}` — كل الطاقم الذين لهم دوام؛ الطابور بترتيب الخدمة (in_service ثم called ثم waiting) مع `eta/etaEnd` المحسوبة الآن؛ العروض المؤقتة (`offered`) لا تظهر.
- `POST /manager/bookings/{id}/transfer` بجسم `{toBarberId}` وترويسة `Idempotency-Key` ← `200 Booking` (عند الحلاق الجديد، مع `customerPhone`). للمدير فقط. يُقبل للحالات `waiting` و`called` فقط (`called` يعود `waiting` ويُستدعى من جديد عند الحلاق الجديد). يُدرج وفق ق4/ق19 عند الحلاق الجديد (لا يتأخر أحد) ويحافظ على `originalEta`؛ يُسجَّل حدث `transferred` (السبب `transferred`) وسجل تدقيق `booking.transferred`، ويصل الزبونَ تنبيه `transferred`، ويصبح الوقت الجديد مرجع ق5. من تقدّم عند الحلاق السابق يُسجَّل تغيّر وقته بالسبب `transferred_ahead` (وتنطبق عليه ق5). تغييرات المزامنة: `booking_removed` للحلاق السابق و`booking_created` للجديد. الأخطاء: `404 BOOKING_NOT_FOUND` / `BARBER_NOT_FOUND`، `409 TRANSFER_SAME_BARBER` / `BOOKING_STARTED` / `BOOKING_NOT_ACTIVE` / `BARBER_NOT_WORKING` / `BARBER_ABSENT` / `BARBER_UNAVAILABLE`، و**`409 TRANSFER_NO_SLOT`** إن لم يتسع يوم الحلاق المختار مع `error.details = {nearest: {barberId, barberName, start, end} | null, alternatives[نفس الشكل، الأقرب أولًا]}` (حلاقون آخرون يتسع عندهم الآن؛ للاسترشاد فقط، لا يُحجز شيء).

## التنبيهات (FCM)
`{type, bookingId, title, body}` — الأنواع: `booking_confirmed`، `called`، `eta_changed`، `postponed`، `no_show`، `cancelled_closing`، `transferred`، `overrun` (للحلاق)، `account_pending`، `barber_not_connected`، `barber_absent`، `sync_conflict`، `base_duration_suspect` (للمدير). قيم `data` نصية. النصوص كما في التصميم §8.
- `transferred` (للزبون): «نُقل حجزك إلى {الحلاق} — الوقت المتوقع {الوقت}»؛ `data` تضيف `eta` و`barberId`.
- `base_duration_suspect` (للمدير، §5.10): حين يُستبعد نصف آخر 10 عينات أو أكثر (5 على الأقل) لحلاق ومجموعة خدمات مقارنةً بالمدة الأساسية — «مدد «{الخدمات}» الفعلية لدى {الحلاق} تختلف كثيرًا عن المدة الأساسية ({س} د) — راجعها من شاشة الخدمات». مرة واحدة لكل مجموعة خدمات في يوم العمل. `data` = `{serviceSetKey, barberId, baseDurationMin}` (بلا `bookingId`).

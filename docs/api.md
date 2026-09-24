# عقد الواجهة البرمجية (v1)

مرجع مشترك للسيرفر وتطبيقي Flutter. مشتق من `design.md` (2.1). الأوقات بصيغة ISO-8601 UTC، والمبالغ أعداد صحيحة بأصغر وحدة للعملة (هللة)، والعملة من ملف الصالون.

## قواعد عامة
- كل الطلبات عبر HTTPS تحت `/v1`. الصالون يُستخرج من رمز الجلسة فقط، لا من الطلب (§7).
- الأخطاء: `{"error": {"code": "SLOT_UNAVAILABLE", "message": "نص عربي للعرض"}}` مع حالة HTTP مناسبة.
- الطلبات التي تنشئ أو تغيّر حجزًا أو دفعًا تحمل ترويسة `Idempotency-Key` (UUID)؛ تكرارها يعيد النتيجة الأولى.
- حدود المعدل تعيد `429` مع `Retry-After`.

## عام (بلا دخول)
| الطلب | الوصف |
|---|---|
| `GET /salons/{code}` | ملف الصالون العام (للصالونات المفعّلة فقط): الاسم، الشعار، النبذة، العنوان، الإحداثيات، وسائل الاتصال، الصور، ساعات العمل، الكتالوج |
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
| `GET /bookings/current` | الحجز النشط: `{booking, eta, originalEta, lastChangeReason, status, progress: {done, ahead}, live, lastUpdateAt}` |
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
| `POST /heartbeat` | `{deviceSeq, queueDigest}` كل 30 ث |
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
- `GET /bookings/current` ← كما أعلاه + `etaEnd, lastChangeReasonCode, dayState, barber{id,name}, serverTime`؛ `404 NO_ACTIVE_BOOKING` إن لم يوجد حجز نشط.
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
| ملف الصالون والصور | `GET/PUT /manager/profile`، `POST/DELETE /manager/photos` |
| الكتالوج | `GET/POST/PUT/DELETE /manager/catalog` |
| الخدمات | `GET/POST/PUT/DELETE /manager/services` |
| الطاقم | `GET/POST/PUT /manager/staff`، `POST /manager/staff/{id}/reset-code` |
| الدوام والاستراحات والإجازات وفترات الحاضرين | `/manager/schedules`، `/manager/breaks`، `/manager/absences` |
| الإعدادات | `GET/PUT /manager/settings` |
| الزبائن | `GET /manager/customers`، `POST …/{id}/approve\|suspend\|reset-code\|link-walkin`، `POST /manager/phone-disputes/{id}/resolve` |
| الطوابير | `GET /manager/queues`، `POST /manager/bookings/{id}/transfer` (ق25) |
| التقارير | `GET /manager/reports?from=&to=` (§9) |

## التنبيهات (FCM)
`{type, bookingId, title, body}` — الأنواع: `booking_confirmed`، `called`، `eta_changed`، `postponed`، `no_show`، `cancelled_closing`، `transferred`، `overrun` (للحلاق)، `account_pending`، `barber_not_connected`، `barber_absent`، `sync_conflict` (للمدير). قيم `data` نصية. النصوص كما في التصميم §8.

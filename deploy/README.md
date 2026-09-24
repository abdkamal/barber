# تشغيل «صالوني» على خادمك (نسخة التجربة)

هذه **نسخة تطوير للتجربة** وليست الإصدار النهائي. كل شيء يعمل داخل Docker على خادم واحد،
ويحصل تلقائيًا على شهادة HTTPS مجانية.

## ما تحتاجه
- خادم VPS بنظام **Ubuntu 22.04/24.04** أو **Debian 12/13**، ذاكرة **2 GB** على الأقل، ودخول إليه بـ SSH.
- فتح المنفذين **80 و443** في لوحة مزوّد الخادم (Firewall / Security group) إن كانت لديه لوحة كهذه.
- **نطاق (دومين) اختياري:** إن لم يكن لديك نطاق فلا مشكلة، سيُستعمل عنوان مجاني مثل
  `203-0-113-7.sslip.io` مبني على IP خادمك. إن كان لديك نطاق فوجّه سجل `A` منه إلى IP الخادم أولًا.

## التثبيت (مرة واحدة)
ادخل إلى الخادم بـ SSH ثم اختر **إحدى** الطريقتين.

> **على Debian:** إن ظهر `sudo: command not found` فأنت غالبًا تدخل بحساب `root`؛ نفّذ الأوامر نفسها **بدون كلمة `sudo`**.

### الطريقة 1: من GitHub مباشرة
```bash
sudo apt-get update && sudo apt-get install -y git
sudo git clone -b claude/ecstatic-wozniak-fn1302 https://github.com/abdkamal/barber.git /opt/saloni
sudo bash /opt/saloni/deploy/install.sh
```
إن كان المستودع خاصًا فسيطلب `git` اسم المستخدم وكلمة المرور: اكتب اسمك في GitHub، وبدل كلمة المرور
الصق **رمز وصول** (GitHub ← Settings ← Developer settings ← Personal access tokens، بصلاحية قراءة المستودع).

### الطريقة 2: من ملف مضغوط ترفعه بنفسك
1. من جهازك نزّل الملف (وأنت مسجّل الدخول في GitHub):
   `https://github.com/abdkamal/barber/archive/refs/heads/claude/ecstatic-wozniak-fn1302.tar.gz`
   وسمِّه `saloni.tar.gz`.
2. ارفعه إلى الخادم (من جهازك، في PowerShell أو الطرفية):
   ```bash
   scp saloni.tar.gz root@IP-الخادم:/root/
   ```
3. على الخادم:
   ```bash
   sudo mkdir -p /opt/saloni
   sudo tar -xzf /root/saloni.tar.gz -C /opt/saloni --strip-components=1
   sudo bash /opt/saloni/deploy/install.sh
   ```

**عندك نطاق؟** أضفه لأمر التثبيت: `sudo bash /opt/saloni/deploy/install.sh --domain api.example.com`

التثبيت يأخذ **5–15 دقيقة** أول مرة، ويمكن إعادة تشغيله بأمان في أي وقت (لا يمسح البيانات ولا يغيّر الأسرار).
في النهاية يطبع **عنوان السيرفر**، مثل: `https://203-0-113-7.sslip.io`

## كيف أعرف أنه يعمل؟
افتح في المتصفح: `https://<عنوانك>/v1/health` ← يجب أن ترى `{"status":"ok"}`.
أرسل لنا هذا العنوان (بدون `/v1`): تُبنى عليه نسختا تطبيقي الطاقم والزبون للتجربة.

## تفعيل الصالون بعد التسجيل من التطبيق
صاحب الصالون يسجّل من تطبيق الطاقم فيحصل على رمز مثل `RAHA-27`. الصالون لا يظهر للزبائن حتى تفعّله:
```bash
sudo bash /opt/saloni/deploy/vendor.sh pending           # الصالونات بانتظار التفعيل
sudo bash /opt/saloni/deploy/vendor.sh activate RAHA-27  # التفعيل
```
أوامر أخرى: `list` (كل الصالونات)، `suspend <الرمز>` (إيقاف)،
`reset-manager-password <الرمز>` (رمز لمرة واحدة لإعادة كلمة مرور المدير)، `cleanup-pending` (حذف تسجيلات قديمة لم تُفعَّل).
للقائمة: `sudo bash /opt/saloni/deploy/vendor.sh`

## النسخ الاحتياطي
```bash
sudo bash /opt/saloni/deploy/backup.sh
```
يحفظ قاعدة البيانات كاملة والصور في `/opt/saloni/deploy/backups/` ويُبقي آخر 14 نسخة.
**نسخة يومية تلقائية:** نفّذ `sudo crontab -e` وأضف في آخر الملف:
```
30 3 * * * bash /opt/saloni/deploy/backup.sh >> /var/log/saloni-backup.log 2>&1
```
انسخ مجلد `backups` إلى جهازك من حين لآخر. واحتفظ بنسخة من الملف `deploy/.env` في مكان آمن (فيه الأسرار).

## التحديث إلى نسخة أحدث
```bash
sudo bash /opt/saloni/deploy/update.sh
```
يأخذ نسخة احتياطية، يجلب الكود الجديد، يعيد البناء والتشغيل، وتبقى كل البيانات.
إن ثبّتَّ بالطريقة 2: فك الملف الجديد فوق المجلد بالأمر نفسه في الخطوة 3، ثم:
`sudo bash /opt/saloni/deploy/update.sh --no-pull`

## حل المشكلات
| المشكلة | الحل |
|---|---|
| «السيرفر يعمل لكن العنوان العام لم يستجب» | افتح المنفذين 80 و443 في لوحة المزوّد، ثم أعد `install.sh`. إن كان لديك نطاق فتأكد أن سجل `A` يشير إلى IP الخادم |
| أريد رؤية ما يحدث | `cd /opt/saloni/deploy && sudo docker compose logs --tail 100 server` (أو `caddy` لمشاكل HTTPS) |
| حالة الخدمات | `cd /opt/saloni/deploy && sudo docker compose ps` — يجب أن تكون كلها `Up` و`healthy` |
| إعادة التشغيل | `cd /opt/saloni/deploy && sudo docker compose restart` |
| إيقاف كل شيء | `cd /opt/saloni/deploy && sudo docker compose down` (البيانات تبقى) |
| تغيير النطاق لاحقًا | `sudo bash /opt/saloni/deploy/install.sh --domain نطاقك` |
| استرجاع نسخة احتياطية | `cd /opt/saloni/deploy && sudo docker compose stop server pgbouncer` ثم `zcat backups/saloni-db-XXXX.sql.gz \| sudo docker compose exec -T postgres psql -q -U saloni -d postgres` ثم `sudo docker compose start pgbouncer server` (رسالتا خطأ عن الدور `saloni` طبيعيتان) |

**تنبيه:** الإشعارات الفورية (Firebase) معطّلة في هذه النسخة؛ التطبيقات تتحدّث تلقائيًا بالمزامنة الدورية.
لا تحذف الملف `deploy/.env` ولا تعدّل أسراره، وإلا لن تعمل قاعدة البيانات الحالية وستُسجَّل خروج كل الحسابات.

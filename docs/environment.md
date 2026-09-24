# بيئة التطوير (المرحلة 3)

فُحصت في بيئة العمل السحابية بتاريخ 2026-09-24.

| الأداة | الإصدار | الحالة |
|---|---|---|
| Node.js / npm | 22.22 / 10.9 | ✅ |
| Docker | 29.3 (يلزم تشغيل `dockerd`) | ✅ |
| PostgreSQL | 16 (صورة `postgres:16-alpine`) | ✅ |
| PgBouncer | صورة `edoburu/pgbouncer` (وضع transaction) | ✅ مجرَّب مع PostgreSQL |
| Flutter / Dart | 3.47.5 stable / 3.13.4 في `/opt/sdk/flutter` | ✅ إنشاء مشروع، مكتبات pub.dev، اختبارات، بناء ويب |
| Chromium (لتشغيل نسخة الويب والفحص) | `/opt/pw-browsers/chromium-*/chrome-linux/chrome` | ✅ |
| Java (لـ Gradle) | OpenJDK 21 | ✅ |
| **Android SDK** | — | ❌ **محجوب**: `dl.google.com` مرفوض من سياسة الشبكة |

## المعوّق
بناء تطبيقات أندرويد (APK) يحتاج Android SDK من `dl.google.com`. الحل: إضافة النطاق إلى
النطاقات المسموحة في إعدادات شبكة البيئة. `maven.google.com` و`services.gradle.org` متاحان.

حتى ذلك الحين: التطوير والاختبارات وتشغيل التطبيقات كنسخة ويب ممكنة؛ بناء APK للتجربة على الهاتف
(المرحلة 11) يتطلب حل المعوّق.

## ملاحظة
بيئة العمل مؤقتة؛ Flutter المثبت في `/opt/sdk` يُفقد عند إعادة تشغيلها. إعادة التثبيت:
```
mkdir -p /opt/sdk && cd /opt/sdk
curl -sSO https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.5-stable.tar.xz
tar -xf flutter_linux_3.47.5-stable.tar.xz && git config --global --add safe.directory /opt/sdk/flutter
export PATH=/opt/sdk/flutter/bin:$PATH CHROME_EXECUTABLE=$(ls -d /opt/pw-browsers/chromium*/chrome-linux*/chrome | head -1)
```
يُقترح لاحقًا أتمتة ذلك بسكربت بدء للجلسة.

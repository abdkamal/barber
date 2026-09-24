# infra — بيئة التطوير

PostgreSQL 16 + PgBouncer (وضع `transaction`) للتطوير المحلي والاختبارات. **ليست إعداد إنتاج.**

```bash
# إن لم يكن Docker يعمل:  dockerd > /tmp/dockerd.log 2>&1 &
docker compose -f infra/docker-compose.yml up -d --wait
docker compose -f infra/docker-compose.yml down        # إيقاف (البيانات تبقى في volume)
docker compose -f infra/docker-compose.yml down -v     # إيقاف ومسح البيانات
```

| الخدمة | المنفذ على الجهاز | الاستخدام |
|---|---|---|
| `postgres` | 5432 | اتصالات الإدارة المباشرة: إنشاء قواعد الصالونات والترحيل |
| `pgbouncer` | 6432 | اتصالات التشغيل للسيرفر (قاعدة الدليل وقواعد الصالونات) |

- PgBouncer مضبوط بمدخل عام `*` فتصل كل قاعدة صالون تُنشأ لاحقًا دون تعديل إعداده.
- بيانات الدخول الافتراضية للتطوير: `saloni` / `saloni_dev_password` (يمكن تغييرها بمتغيرات
  `SALONI_PG_USER` و`SALONI_PG_PASSWORD`، والمنافذ بـ `SALONI_PG_PORT` و`SALONI_PGBOUNCER_PORT`).

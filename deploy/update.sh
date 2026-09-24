#!/usr/bin/env bash
# Update to the latest code and restart — data (databases, images, certificates, .env) is kept.
#   sudo bash deploy/update.sh            # git pull (if this is a git clone) + backup + rebuild + restart
#   sudo bash deploy/update.sh --no-pull  # after extracting a newer uploaded archive over this folder
set -euo pipefail
# shellcheck source=deploy/_common.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
need_root
[ -f "$ENV_FILE" ] || die "لم أجد deploy/.env — شغّل التثبيت أولًا: sudo bash $DEPLOY_DIR/install.sh"

if [ "${1:-}" != "--no-pull" ]; then
  if [ -d "$APP_DIR/.git" ]; then
    say "جلب آخر نسخة من الكود…"
    git -C "$APP_DIR" pull --ff-only
  else
    warn "هذه النسخة ليست من git — سأعيد البناء من الملفات الموجودة كما هي."
  fi
fi

if [ -n "$(dc ps -q --status running postgres 2>/dev/null)" ]; then
  say "نسخة احتياطية قبل التحديث…"
  bash "$DEPLOY_DIR/backup.sh" || warn "تعذّرت النسخة الاحتياطية (أكمل التحديث)."
fi

say "إعادة البناء…"
dc build server
say "إعادة التشغيل (تُطبَّق ترحيلات قاعدة البيانات تلقائيًا)…"
dc up -d --remove-orphans
wait_server_healthy 300 || { dc logs --tail 60 server; die "السيرفر لم يصبح جاهزًا بعد التحديث."; }
docker image prune -f >/dev/null 2>&1 || true

DOMAIN="$(env_get SALONI_DOMAIN)"
if wait_public_health "$DOMAIN"; then
  ok "تم التحديث: https://$DOMAIN/v1/health"
else
  warn "السيرفر يعمل داخليًا لكن https://$DOMAIN لم يستجب بعد."
fi

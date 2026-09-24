#!/usr/bin/env bash
# Enable push notifications (Firebase Cloud Messaging) on the server.
#   sudo bash deploy/enable-push.sh /path/to/service-account.json
# The file is the Firebase "service account" private key (Project settings → Service accounts →
# Generate new private key). It is copied to deploy/secrets/fcm.json (readable only by the server
# container), FCM_SERVICE_ACCOUNT_FILE is set in deploy/.env and the server is restarted.
set -euo pipefail
# shellcheck source=deploy/_common.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
need_root
[ -f "$ENV_FILE" ] || die "لم أجد deploy/.env — شغّل التثبيت أولًا: sudo bash $DEPLOY_DIR/install.sh"
SRC="${1:-}"
if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then die "حدّد مسار ملف مفتاح Firebase، مثال: sudo bash $0 /root/firebase-key.json"; fi
if ! { grep -q '"type": *"service_account"' "$SRC" && grep -q '"private_key"' "$SRC" && grep -q '"client_email"' "$SRC"; }; then
  die "هذا ليس ملف «حساب خدمة» من Firebase (Service account). نزّله من: إعدادات المشروع ← Service accounts ← Generate new private key"
fi
PROJECT="$(sed -n 's/.*"project_id": *"\([^"]*\)".*/\1/p' "$SRC" | head -n1)"

install -d -m 700 -o 1000 -g 1000 "$DEPLOY_DIR/secrets"
install -m 600 -o 1000 -g 1000 "$SRC" "$DEPLOY_DIR/secrets/fcm.json"
if grep -q '^FCM_SERVICE_ACCOUNT_FILE=' "$ENV_FILE"; then
  sed -i 's|^FCM_SERVICE_ACCOUNT_FILE=.*|FCM_SERVICE_ACCOUNT_FILE=/run/saloni-secrets/fcm.json|' "$ENV_FILE"
else
  echo 'FCM_SERVICE_ACCOUNT_FILE=/run/saloni-secrets/fcm.json' >>"$ENV_FILE"
fi
ok "نُسخ المفتاح (المشروع: ${PROJECT:-?})"

say "إعادة تشغيل السيرفر…"
dc up -d server
wait_server_healthy 180 || { dc logs --tail 40 server; die "السيرفر لم يصبح جاهزًا — انظر السجل أعلاه."; }
ok "الإشعارات مفعّلة على السيرفر. يمكنك الآن حذف الملف الأصلي: rm $SRC"

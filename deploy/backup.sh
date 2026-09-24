#!/usr/bin/env bash
# Backup: all databases (pg_dumpall) + uploaded images → deploy/backups/, keeps the newest 14 of each.
#   sudo bash deploy/backup.sh
# Daily at 03:30 (as root: crontab -e), adjust the path to where the project lives:
#   30 3 * * * bash /opt/saloni/deploy/backup.sh >> /var/log/saloni-backup.log 2>&1
set -euo pipefail
# shellcheck source=deploy/_common.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
need_root

umask 077
KEEP="${KEEP:-14}"
BACKUP_DIR="$DEPLOY_DIR/backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

[ -n "$(dc ps -q --status running postgres 2>/dev/null)" ] || die "قاعدة البيانات غير مشغّلة."

DB_FILE="$BACKUP_DIR/saloni-db-$STAMP.sql.gz"
dc exec -T postgres pg_dumpall -U saloni --clean --if-exists | gzip -9 >"$DB_FILE.part"
mv "$DB_FILE.part" "$DB_FILE"
ok "قاعدة البيانات: $DB_FILE ($(du -h "$DB_FILE" | cut -f1))"

if [ -n "$(dc ps -q --status running server 2>/dev/null)" ]; then
  MEDIA_FILE="$BACKUP_DIR/saloni-media-$STAMP.tar.gz"
  dc exec -T server tar -czf - -C /data storage >"$MEDIA_FILE.part"
  mv "$MEDIA_FILE.part" "$MEDIA_FILE"
  ok "الصور: $MEDIA_FILE ($(du -h "$MEDIA_FILE" | cut -f1))"
fi

# Keep only the newest $KEEP of each kind (file names sort by date).
for kind in db media; do
  find "$BACKUP_DIR" -maxdepth 1 -type f -name "saloni-$kind-*" -printf '%f\n' | sort -r | tail -n +"$((KEEP + 1))" |
    while read -r f; do rm -f -- "${BACKUP_DIR:?}/${f:?}"; done
done
ok "تم. يُحتفظ بآخر $KEEP نسخة."

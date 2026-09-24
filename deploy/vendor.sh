#!/usr/bin/env bash
# Vendor (system provider) commands, run inside the server container.
#   sudo bash deploy/vendor.sh pending                         # salons waiting for activation
#   sudo bash deploy/vendor.sh activate RAHA-27                # activate a salon
#   sudo bash deploy/vendor.sh list [--status active]          # all salons
#   sudo bash deploy/vendor.sh suspend RAHA-27
#   sudo bash deploy/vendor.sh reset-manager-password RAHA-27 [--username owner]   # one-time code (24 h)
#   sudo bash deploy/vendor.sh cleanup-pending [--older-than-days 14] [--dry-run]
set -euo pipefail
# shellcheck source=deploy/_common.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
need_root

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  cat <<'HELP'
أوامر المزوّد:
  pending                                   الصالونات بانتظار التفعيل
  activate <CODE>                           تفعيل صالون (مثال: activate RAHA-27)
  list [--status pending_activation|active|suspended]   كل الصالونات
  suspend <CODE>                            إيقاف صالون
  reset-manager-password <CODE> [--username <name>]   رمز لمرة واحدة لإعادة كلمة مرور المدير (24 ساعة)
  cleanup-pending [--older-than-days 14] [--dry-run]  حذف صالونات لم تُفعَّل وأقدم من المدة
HELP
  exit 0
fi

[ -n "$(dc ps -q --status running server 2>/dev/null)" ] || die "السيرفر غير مشغّل. شغّله أولًا: sudo bash $DEPLOY_DIR/install.sh"
dc exec -T server node dist/cli/vendor.js "$@"

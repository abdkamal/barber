#!/bin/sh
# Saloni container entrypoint.
#   serve              → apply database migrations (directory, then every salon DB), then start the API
#   migrate            → migrations only
#   vendor <args...>   → vendor CLI (list, pending, activate, suspend, reset-manager-password, cleanup-pending)
#   anything else      → executed as-is
set -e
cd /app/server
case "${1:-serve}" in
  serve)
    echo "saloni: applying migrations…"
    node dist/cli/migrate.js
    echo "saloni: starting API server"
    exec node dist/main.js
    ;;
  migrate)
    exec node dist/cli/migrate.js
    ;;
  vendor)
    shift
    exec node dist/cli/vendor.js "$@"
    ;;
  *)
    exec "$@"
    ;;
esac

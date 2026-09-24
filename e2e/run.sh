#!/usr/bin/env bash
# End-to-end test: boots the REAL Saloni server (ts-node, against the compose
# PostgreSQL + PgBouncer from infra/) on its own databases and drives it with the
# REAL Dart ApiClient + StaffSyncEngine (e2e/test/full_flow_test.dart).
#
#   e2e/run.sh            # from anywhere
#
# Isolation: databases `saloni_e2e_directory` / `saloni_e2e_salon_*` (dropped and
# recreated on every run — never the dev or `saloni_test_*` ones), port 3790
# (override with E2E_PORT), uploads under e2e/.tmp/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
E2E="$ROOT/e2e"
SERVER="$ROOT/server"
COMPOSE="$ROOT/infra/docker-compose.yml"
PORT="${E2E_PORT:-3790}"
export PATH="/opt/sdk/flutter/bin:$PATH"

log() { printf '\n== %s\n' "$*"; }

# ---- 1. PostgreSQL + PgBouncer -------------------------------------------------
if ! docker info >/dev/null 2>&1; then
  log "starting dockerd"
  (dockerd >/tmp/dockerd.log 2>&1 &)
  for _ in $(seq 1 60); do docker info >/dev/null 2>&1 && break; sleep 1; done
fi
log "compose up (postgres + pgbouncer)"
docker compose -f "$COMPOSE" up -d --wait

# ---- 2. Fresh e2e databases -----------------------------------------------------
log "dropping previous saloni_e2e_* databases"
DBS=$(docker compose -f "$COMPOSE" exec -T postgres psql -U saloni -d postgres -Atc \
  "SELECT datname FROM pg_database WHERE datname LIKE 'saloni\_e2e\_%'")
for db in $DBS; do
  docker compose -f "$COMPOSE" exec -T postgres psql -U saloni -d postgres -qc \
    "DROP DATABASE IF EXISTS \"$db\" WITH (FORCE)" >/dev/null
done

export NODE_ENV=development
export PORT HOST=127.0.0.1
export DIRECTORY_DB_NAME=saloni_e2e_directory
export SALON_DB_PREFIX=saloni_e2e_salon_
export DIRECTORY_CACHE_TTL_MS=200
export STORAGE_DIR="$E2E/.tmp/storage"
export SCHEDULER_ENABLED=true
export E2E_BASE_URL="http://127.0.0.1:$PORT"
export E2E_SERVER_DIR="$SERVER"
mkdir -p "$STORAGE_DIR"

# ---- 3. Server: engine build, migrations, boot ----------------------------------
cd "$SERVER"
[ -d "$ROOT/node_modules" ] || (cd "$ROOT" && npm install)
log "building @saloni/engine"
npm run --silent build:engine
log "migrating $DIRECTORY_DB_NAME"
npx ts-node --transpile-only src/cli/migrate.ts

log "starting server on :$PORT"
npx ts-node --transpile-only src/main.ts >"$E2E/.tmp/server.log" 2>&1 &
SERVER_PID=$!
cleanup() { kill "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" 2>/dev/null || true; }
trap cleanup EXIT
for _ in $(seq 1 90); do
  if curl -fsS "$E2E_BASE_URL/v1/health" >/dev/null 2>&1; then break; fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "server exited early:"; cat "$E2E/.tmp/server.log"; exit 1
  fi
  sleep 1
done
curl -fsS "$E2E_BASE_URL/v1/health"; echo

# ---- 4. Dart e2e -------------------------------------------------------------------
cd "$E2E"
log "dart test (e2e)"
flutter pub get >/dev/null
set +e
dart test --reporter expanded "$@"
STATUS=$?
set -e
if [ $STATUS -ne 0 ]; then
  echo; echo "---- server log (tail) ----"; tail -n 80 "$E2E/.tmp/server.log"
fi
exit $STATUS

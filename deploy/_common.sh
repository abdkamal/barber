# shellcheck shell=bash
# Shared helpers for the Saloni deploy scripts (sourced, not executed).

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$DEPLOY_DIR/.." && pwd)"
ENV_FILE="$DEPLOY_DIR/.env"
export DEPLOY_DIR APP_DIR ENV_FILE

say()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✔\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m✘ %s\033[0m\n' "$*" >&2; exit 1; }

need_root() {
  [ "$(id -u)" -eq 0 ] || die "شغّل الأمر بصلاحية الجذر: أضف sudo في أوله (مثال: sudo bash $0)"
}

# docker compose bound to this deploy directory and its .env.
# Edge mode (SALONI_EDGE_NETWORK set): another proxy owns 80/443, so Saloni's Caddy stays off and the
# API joins that proxy's network. Otherwise the "own-proxy" profile starts Saloni's Caddy.
dc() {
  if [ -n "$(env_get SALONI_EDGE_NETWORK)" ]; then
    docker compose --project-directory "$DEPLOY_DIR" -f "$DEPLOY_DIR/docker-compose.yml" \
      -f "$DEPLOY_DIR/docker-compose.edge.yml" --env-file "$ENV_FILE" "$@"
  else
    COMPOSE_PROFILES=own-proxy docker compose --project-directory "$DEPLOY_DIR" \
      -f "$DEPLOY_DIR/docker-compose.yml" --env-file "$ENV_FILE" "$@"
  fi
}

env_get() { # KEY → value from deploy/.env (empty if absent)
  [ -f "$ENV_FILE" ] || return 0
  sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1
}

# Wait until the server container reports healthy (migrations done, DB reachable). $1 = timeout seconds.
wait_server_healthy() {
  local timeout="${1:-240}" waited=0 id status
  while [ "$waited" -lt "$timeout" ]; do
    id="$(dc ps -q server 2>/dev/null || true)"
    if [ -n "$id" ]; then
      status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id" 2>/dev/null || true)"
      [ "$status" = "healthy" ] && return 0
    fi
    sleep 3; waited=$((waited + 3))
  done
  return 1
}

# Check the public HTTPS URL (certificate issuance can take a minute). $1 = domain.
wait_public_health() {
  local domain="$1" i
  for i in $(seq 1 30); do
    if curl -fsS --max-time 10 "https://$domain/v1/health" >/dev/null 2>&1; then
      [ "$i" -gt 1 ] && echo
      return 0
    fi
    [ "$i" -eq 1 ] && printf 'بانتظار شهادة HTTPS'
    printf '.'; sleep 5
  done
  echo
  return 1
}

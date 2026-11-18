#!/usr/bin/env bash
# Local end-to-end smoke test: build the image, start postgres + migrate + web with
# docker compose, probe the endpoints, then tear everything down. Local only: no
# registry login, no push.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DOCKER="${DOCKER:-docker}"
PORT="${WEB_PORT:-8000}"
BASE="http://127.0.0.1:${PORT}"
export WEB_PORT="$PORT"

# SMOKE_HOST_NETWORK=1 runs every service on the host network (for sandboxes where
# dockerd runs with --iptables=false and container DNS is unavailable).
COMPOSE=("$DOCKER" compose -f compose.yaml)
OVERRIDE=""
if [ "${SMOKE_HOST_NETWORK:-0}" = "1" ]; then
  OVERRIDE="$(mktemp --suffix=.yaml)"
  cat >"$OVERRIDE" <<YAML
services:
  db:
    network_mode: host
  migrate:
    network_mode: host
    environment: {DB_HOST: 127.0.0.1}
  web:
    network_mode: host
    ports: !reset []
    environment: {DB_HOST: 127.0.0.1, PORT: "${PORT}"}
YAML
  COMPOSE+=(-f "$OVERRIDE")
fi

cleanup() {
  "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
  [ -z "$OVERRIDE" ] || rm -f "$OVERRIDE"
}
trap cleanup EXIT

echo "==> docker build (local tag only)"
# DOCKER_BUILD_NETWORK=host helps on hosts where the default bridge has no NAT.
$DOCKER build ${DOCKER_BUILD_NETWORK:+--network "$DOCKER_BUILD_NETWORK"} \
  --build-arg APP_VERSION=0.0.0-smoke --build-arg GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo local)" \
  -t release-ledger:local .

echo "==> docker compose up"
"${COMPOSE[@]}" up -d --no-build

echo "==> waiting for ${BASE}/healthz"
for _ in $(seq 1 60); do
  if curl -fsS "${BASE}/healthz" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

fail() {
  echo "FAIL: $*" >&2
  "${COMPOSE[@]}" logs --no-color >&2 || true
  exit 1
}

curl -fsS "${BASE}/healthz" | grep -q '"ok"' || fail "liveness"
curl -fsS "${BASE}/readyz" | grep -q '"database": "ok"' || fail "readiness (postgres)"
curl -fsS "${BASE}/api/releases/" | grep -q 'payments-api' || fail "seeded releases API"
curl -fsS "${BASE}/api/releases/current/" | grep -q '"prod"' || fail "summary API"
curl -fsS "${BASE}/" | grep -q 'Release Ledger' || fail "index page"
static_path="$(curl -fsS "${BASE}/" | grep -o '/static/ledger/site\.[0-9a-f]*\.css' | head -n1)"
[ -n "$static_path" ] || fail "hashed static asset link"
curl -fsS -o /dev/null "${BASE}${static_path}" || fail "static asset via WhiteNoise"
code="$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: evil.example.com' "${BASE}/version")"
[ "$code" = "400" ] || fail "unknown Host should be rejected, got ${code}"

uid="$("${COMPOSE[@]}" exec -T web id -u)"
[ "$uid" = "10001" ] || fail "web runs as uid ${uid}, expected 10001"
if "${COMPOSE[@]}" exec -T web sh -c 'touch /srv/app/should-fail' 2>/dev/null; then
  fail "root filesystem is writable"
fi

"${COMPOSE[@]}" exec -T web python /srv/app/healthcheck.py || fail "container healthcheck script"
health="$($DOCKER inspect --format '{{.State.Health.Status}}' "$("${COMPOSE[@]}" ps -q web)")"
echo "container health: ${health}"

echo "Compose smoke test passed."

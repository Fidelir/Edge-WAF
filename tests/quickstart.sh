#!/usr/bin/env bash
# README quick start with docker-compose.yml (host network mode): tests/quickstart.sh [image]
# Needs ports 80, 443, 127.0.0.1:8080 and 127.0.0.1:8099 free on the Docker host and no container named "waf".
set -euo pipefail

IMAGE="${1:-edge-waf:local}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
PROJECT="edge-waf-quickstart-$$"
APP="edge-waf-quickstart-app-$$"
failed=0

compose() {
    WAF_IMAGE="$IMAGE" docker compose -f "$ROOT/docker-compose.yml" --project-directory "$TMP" -p "$PROJECT" "$@"
}

trap 'compose down >/dev/null 2>&1 || true; docker rm -f "$APP" >/dev/null 2>&1 || true; rm -rf "$TMP" 2>/dev/null || true' EXIT

ok()   { echo "ok    $*"; }
fail() { echo "FAIL  $*"; failed=1; }

# Runs in the host network namespace (on Docker Desktop that is the Docker VM).
req() {
    docker run --rm --network host nginx:stable-alpine curl -s -o /dev/null -w '%{http_code}' "http://localhost$1"
}

expect_status() {
    local name="$1" want="$2" got
    got="$(req "$3")"
    if [[ "$got" == "$want" ]]; then ok "$name -> $got"; else fail "$name: expected $want, got $got"; fi
}

expect_file() {
    if grep -qE -- "$3" "$TMP/logs/$2" 2>/dev/null; then ok "$1"; else fail "$1: /$3/ not found in logs/$2"; fi
}

mkdir -p "$TMP/conf.d" "$TMP/ssl.d" "$TMP/logs"
cp "$ROOT/conf.d/default.conf" "$TMP/conf.d/"
cp "$ROOT/examples/quickstart-http.conf" "$TMP/conf.d/quickstart.conf"

docker run -d --name "$APP" -p 127.0.0.1:8080:80 nginx:stable-alpine >/dev/null
compose up -d --no-build

cid="$(compose ps -q waf)"
for _ in $(seq 1 30); do
    [[ "$(docker inspect -f '{{.State.Health.Status}}' "$cid")" == healthy ]] && break
    sleep 1
done
if [[ "$(docker inspect -f '{{.State.Health.Status}}' "$cid")" == healthy ]]; then
    ok "container healthy"
else
    docker logs "$cid" 2>&1 | tail -n 20
    fail "container did not become healthy"
    exit 1
fi

expect_status "GET / reaches the app" 200 "/"
expect_status "GET /.env blocked by the probe guard" 403 "/.env"
expect_status "SQLi passes in DetectionOnly" 200 "/?id=1%27%20OR%20%271%27%3D%271"
sleep 1
expect_file "probe in access.log with deny_probe=1" access.log '"request_uri":"/\.env".*"deny_probe":"1"'
expect_file "SQLi in modsec_audit.log (CRS 942xxx)" modsec_audit.log '"ruleId":"942[0-9]+"'

exit "$failed"

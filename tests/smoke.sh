#!/usr/bin/env bash
# Smoke tests against a built image: tests/smoke.sh [image]
set -euo pipefail

IMAGE="${1:-edge-waf:local}"
HERE="$(cd "$(dirname "$0")" && pwd)"
NET="waf-smoke-$$"
BACKEND="waf-smoke-backend-$$"
WAF="waf-smoke-waf-$$"
failed=0

trap 'docker rm -f "$WAF" "$BACKEND" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true' EXIT

ok()   { echo "ok    $*"; }
fail() { echo "FAIL  $*"; failed=1; }

req() {
    docker exec "$BACKEND" curl -s -o /dev/null -w '%{http_code}' --path-as-is -A 'smoke-test/1.0' "http://waf$1"
}

expect_status() {
    local name="$1" want="$2" got
    got="$(req "$3")"
    if [[ "$got" == "$want" ]]; then ok "$name -> $got"; else fail "$name: expected $want, got $got"; fi
}

expect_log() {
    if docker logs "$WAF" 2>&1 | grep -qE -- "$2"; then ok "$1"; else fail "$1: /$2/ not found in logs"; fi
}

start_waf() {
    docker rm -f "$WAF" >/dev/null 2>&1 || true
    docker run -d --name "$WAF" --network "$NET" --network-alias waf \
        -e MODSECURITY_ENGINE="$1" \
        -v "$HERE/conf.d:/etc/nginx/conf.d:ro" \
        "$IMAGE" >/dev/null
    for _ in $(seq 1 30); do
        [[ "$(docker inspect -f '{{.State.Health.Status}}' "$WAF")" == healthy ]] && { ok "container healthy"; return 0; }
        sleep 1
    done
    docker logs "$WAF" 2>&1 | tail -n 20
    fail "container did not become healthy"
    exit 1
}

docker network create "$NET" >/dev/null
docker run -d --name "$BACKEND" --network "$NET" --network-alias backend nginx:stable-alpine >/dev/null

for mode in DetectionOnly On; do
    echo "== MODSECURITY_ENGINE=$mode"
    start_waf "$mode"

    expect_status "GET /" 200 "/"
    expect_status "probe /php.php" 403 "/php.php"
    expect_status "probe /.env" 403 "/.env"
    expect_status "path traversal" 403 "/?file=..%2f..%2fetc%2fpasswd"
    expect_log "probe logged with deny_probe=1" '"request_uri":"/php.php".*"deny_probe":"1"'

    if [[ "$mode" == DetectionOnly ]]; then
        expect_status "SQLi passes (DetectionOnly)" 200 "/?id=1%27%20OR%20%271%27%3D%271"
    else
        expect_status "SQLi blocked (On)" 403 "/?id=1%27%20OR%20%271%27%3D%271"
        expect_status "XSS blocked (On)" 403 "/?q=%3Cscript%3Ealert(1)%3C%2Fscript%3E"
    fi
    expect_log "SQLi in ModSecurity audit log (CRS 942xxx)" '"ruleId":"942[0-9]+"'

    if docker logs "$WAF" 2>&1 | grep -q '\[emerg\]'; then fail "[emerg] in error log"; fi
done

exit "$failed"

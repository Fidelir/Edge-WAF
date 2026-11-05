#!/usr/bin/env bash
# Automatic HTTPS end to end against Pebble, the Let's Encrypt test CA: tests/acme.sh [image]
# Uses examples/auto-https.conf with the test domain, a Pebble issuer and a test backend.
set -euo pipefail

IMAGE="${1:-edge-waf:local}"
PEBBLE_IMAGE=ghcr.io/letsencrypt/pebble:2.10.1
CHALLTESTSRV_IMAGE=ghcr.io/letsencrypt/pebble-challtestsrv:2.10.1
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
ID="waf-acme-$$"
NET="$ID"
SUBNET=10.250.250
WAF_IP="$SUBNET.10"
DOMAIN=site.test
NEW_DOMAIN=new.test
failed=0

trap 'docker rm -f "$ID-waf" "$ID-backend" "$ID-pebble" "$ID-dns" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

ok()   { echo "ok    $*"; }
fail() { echo "FAIL  $*"; failed=1; }

client() {
    docker exec "$ID-backend" curl -s --max-time 5 --resolve "$DOMAIN:80:$WAF_IP" --resolve "$DOMAIN:443:$WAF_IP" \
        --resolve "$NEW_DOMAIN:443:$WAF_IP" "$@"
}

expect() {
    local name="$1" want="$2" got
    shift 2
    got="$(client -o /dev/null -w '%{http_code}' "$@" || true)"
    if [[ "$got" == "$want" ]]; then ok "$name -> $got"; else fail "$name: expected $want, got $got"; fi
}

wait_for_certificate() {
    for _ in $(seq 1 60); do
        if client -k -o /dev/null "https://$1/"; then return 0; fi
        sleep 1
    done
    return 1
}

mkdir -p "$TMP/conf.d" "$TMP/pebble"
cp "$ROOT/conf.d/default.conf" "$TMP/conf.d/"
sed -e "s/app\.example\.com/$DOMAIN/g" \
    -e 's/acme_certificate       letsencrypt;/acme_certificate       pebble;/' \
    -e 's#http://127\.0\.0\.1:8080#http://backend:80#' \
    "$ROOT/examples/auto-https.conf" > "$TMP/conf.d/site.conf"
grep -q 'acme_certificate       pebble;' "$TMP/conf.d/site.conf" || { echo "examples/auto-https.conf changed, update tests/acme.sh"; exit 1; }
cat > "$TMP/conf.d/00-pebble-issuer.conf" <<'EOF'
acme_issuer pebble {
    uri         https://pebble:14000/dir;
    ssl_verify  off;
    state_path  /var/lib/nginx/acme/pebble;
    accept_terms_of_service;
}
EOF
cat > "$TMP/pebble/config.json" <<'EOF'
{
  "pebble": {
    "listenAddress": "0.0.0.0:14000",
    "managementListenAddress": "0.0.0.0:15000",
    "certificate": "test/certs/localhost/cert.pem",
    "privateKey": "test/certs/localhost/key.pem",
    "httpPort": 80,
    "tlsPort": 443,
    "ocspResponderURL": "",
    "externalAccountBindingRequired": false
  }
}
EOF

docker network create --subnet "$SUBNET.0/24" "$NET" >/dev/null
docker run -d --name "$ID-dns" --network "$NET" --ip "$SUBNET.20" "$CHALLTESTSRV_IMAGE" \
    -defaultIPv4 "$WAF_IP" -defaultIPv6 "" -http01 "" -https01 "" -tlsalpn01 "" -doh "" >/dev/null
docker run -d --name "$ID-pebble" --network "$NET" --network-alias pebble \
    -e PEBBLE_VA_NOSLEEP=1 -e PEBBLE_WFE_NONCEREJECT=0 \
    -v "$TMP/pebble:/config:ro" "$PEBBLE_IMAGE" -config /config/config.json -dnsserver "$SUBNET.20:8053" >/dev/null
docker run -d --name "$ID-backend" --network "$NET" --network-alias backend nginx:stable-alpine >/dev/null
docker run -d --name "$ID-waf" --network "$NET" --ip "$WAF_IP" \
    -v "$TMP/conf.d:/etc/nginx/conf.d:ro" "$IMAGE" >/dev/null

if wait_for_certificate "$DOMAIN"; then
    ok "certificate issued"
else
    docker logs "$ID-waf" 2>&1 | tail -n 20
    docker logs "$ID-pebble" 2>&1 | tail -n 10
    fail "no certificate within 60 s"
    exit 1
fi

issuer="$(client -k -v -o /dev/null "https://$DOMAIN/" 2>&1 | grep -i 'issuer:' || true)"
if [[ "$issuer" == *Pebble* ]]; then ok "certificate issued by Pebble"; else fail "unexpected issuer: $issuer"; fi
expect "HTTP redirects to HTTPS" 301 "http://$DOMAIN/"
expect "HTTPS reaches the backend" 200 -k "https://$DOMAIN/"
expect "HTTPS probe blocked" 403 -k "https://$DOMAIN/.env"

state="$(docker exec "$ID-waf" find /var/lib/nginx/acme/pebble -type f -user nginx | wc -l)"
if (( state > 0 )); then ok "state saved ($state files)"; else fail "no state files in /var/lib/nginx/acme/pebble"; fi

docker restart "$ID-waf" >/dev/null
if wait_for_certificate "$DOMAIN"; then ok "HTTPS after restart"; else fail "no HTTPS after restart"; fi
issued="$(docker logs "$ID-pebble" 2>&1 | grep -c 'Issued certificate serial' || true)"
if [[ "$issued" == 1 ]]; then ok "certificate reused after restart"; else fail "Pebble issued $issued certificates, expected 1"; fi

sed "s/$DOMAIN/$NEW_DOMAIN/g" "$TMP/conf.d/site.conf" > "$TMP/conf.d/new.conf"
docker exec "$ID-waf" nginx -s reload 2>/dev/null
if wait_for_certificate "$NEW_DOMAIN"; then
    ok "certificate issued for a site added by reload"
else
    fail "no certificate for $NEW_DOMAIN within 60 s after reload"
fi

if docker logs "$ID-waf" 2>&1 | grep -q '\[emerg\]'; then fail "[emerg] in error log"; fi
exit "$failed"

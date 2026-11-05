#!/usr/bin/env bash
# Validates examples/*.conf with nginx -t: tests/examples.sh [image]
set -euo pipefail

IMAGE="${1:-edge-waf:local}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=test \
    -keyout "$TMP/privkey.pem" -out "$TMP/fullchain.pem" 2>/dev/null
chmod 0644 "$TMP/privkey.pem"

mkdir -p "$TMP/ssl.d"
grep -ho '/etc/nginx/ssl.d/[^/]*' "$ROOT"/examples/*.conf | sort -u | while read -r path; do
    dir="$TMP/ssl.d/${path#/etc/nginx/ssl.d/}"
    mkdir -p "$dir"
    cp "$TMP/fullchain.pem" "$TMP/privkey.pem" "$dir/"
done

sites=()
for f in "$ROOT"/examples/*.conf; do
    [[ "$(basename "$f")" == realip-* ]] || sites+=("$f")
done

for realip in "$ROOT"/examples/realip-*.conf; do
    conf="$TMP/conf.d-$(basename "$realip" .conf)"
    mkdir -p "$conf"
    cp "$ROOT/conf.d/default.conf" "${sites[@]}" "$conf/"
    cp "$realip" "$conf/00-realip.conf"
    echo "== default.conf + sites + $(basename "$realip")"
    docker run --rm \
        -v "$conf:/etc/nginx/conf.d:ro" -v "$TMP/ssl.d:/etc/nginx/ssl.d:ro" \
        "$IMAGE" nginx -t
done

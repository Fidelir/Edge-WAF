#!/usr/bin/env bash
# Regenerates nginx/realip/cloudflare.conf from https://www.cloudflare.com/ips/
set -euo pipefail

out="$(cd "$(dirname "$0")/.." && pwd)/nginx/realip/cloudflare.conf"
v4="$(curl -fsSL https://www.cloudflare.com/ips-v4)"
v6="$(curl -fsSL https://www.cloudflare.com/ips-v6)"

ranges="$(printf '%s\n%s\n' "$v4" "$v6" | sed '/^\s*$/d')"
if [[ -z "$ranges" ]] || grep -qvE '^[0-9a-fA-F:.]+/[0-9]{1,3}$' <<<"$ranges"; then
    echo "unexpected response from cloudflare.com/ips" >&2
    exit 1
fi

{
    echo "# Cloudflare edge ranges, https://www.cloudflare.com/ips/"
    echo "# Regenerate with scripts/update-cloudflare-ips.sh"
    sed 's/^/set_real_ip_from /; s/$/;/' <<<"$ranges"
    echo
    echo "real_ip_header CF-Connecting-IP;"
} > "$out"

echo "updated $out ($(wc -l <<<"$ranges") ranges)"

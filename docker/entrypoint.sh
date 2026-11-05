#!/bin/bash
set -euo pipefail

: "${MODSECURITY_ENGINE:=DetectionOnly}"
: "${CRS_PARANOIA_LEVEL:=1}"
: "${CRS_INBOUND_ANOMALY_THRESHOLD:=5}"
: "${CRS_OUTBOUND_ANOMALY_THRESHOLD:=4}"
: "${WAF_HEALTH_PORT:=8099}"
: "${WAF_RESOLVER:=}"
: "${ACME_EMAIL:=}"

ACME_STATE=/var/lib/nginx/acme

die() { echo "entrypoint: $*" >&2; exit 1; }

case "$MODSECURITY_ENGINE" in
    On|DetectionOnly|Off) ;;
    *) die "MODSECURITY_ENGINE must be On, DetectionOnly or Off (got '$MODSECURITY_ENGINE')" ;;
esac
[[ "$CRS_PARANOIA_LEVEL" =~ ^[1-4]$ ]] || die "CRS_PARANOIA_LEVEL must be 1..4 (got '$CRS_PARANOIA_LEVEL')"
[[ "$CRS_INBOUND_ANOMALY_THRESHOLD" =~ ^[1-9][0-9]*$ ]] || die "CRS_INBOUND_ANOMALY_THRESHOLD must be a positive integer"
[[ "$CRS_OUTBOUND_ANOMALY_THRESHOLD" =~ ^[1-9][0-9]*$ ]] || die "CRS_OUTBOUND_ANOMALY_THRESHOLD must be a positive integer"
if [[ ! "$WAF_HEALTH_PORT" =~ ^[0-9]+$ ]] || (( WAF_HEALTH_PORT < 1 || WAF_HEALTH_PORT > 65535 )); then
    die "WAF_HEALTH_PORT must be 1..65535 (got '$WAF_HEALTH_PORT')"
fi
if [[ -n "$ACME_EMAIL" && ! "$ACME_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$ ]]; then
    die "ACME_EMAIL must be an e-mail address (got '$ACME_EMAIL')"
fi

if [[ -z "$WAF_RESOLVER" ]]; then
    WAF_RESOLVER="$(awk '$1 == "nameserver" && $2 !~ /%/ { print ($2 ~ /:/ ? "[" $2 "]" : $2) }' /etc/resolv.conf | xargs)"
fi
[[ -n "$WAF_RESOLVER" ]] || die "no nameserver in /etc/resolv.conf; set WAF_RESOLVER"
resolver_re='^[][0-9A-Fa-f:. ]+$'
[[ "$WAF_RESOLVER" =~ $resolver_re ]] || die "WAF_RESOLVER must be a space-separated list of addresses (got '$WAF_RESOLVER')"

cat > /etc/nginx/modsec/runtime.conf <<EOF
SecRuleEngine ${MODSECURITY_ENGINE}

SecAction \\
    "id:900000,phase:1,pass,t:none,nolog,tag:'OWASP_CRS',\\
    setvar:tx.blocking_paranoia_level=${CRS_PARANOIA_LEVEL}"

SecAction \\
    "id:900110,phase:1,pass,t:none,nolog,tag:'OWASP_CRS',\\
    setvar:tx.inbound_anomaly_score_threshold=${CRS_INBOUND_ANOMALY_THRESHOLD},\\
    setvar:tx.outbound_anomaly_score_threshold=${CRS_OUTBOUND_ANOMALY_THRESHOLD}"
EOF

cat > /etc/nginx/runtime/health.conf <<EOF
server {
    listen 127.0.0.1:${WAF_HEALTH_PORT};
    server_name _;
    access_log off;
    modsecurity off;

    location = /healthz {
        default_type text/plain;
        return 200 "ok\n";
    }

    location / {
        return 404;
    }
}
EOF

acme_issuer() {
    printf 'acme_issuer %s {\n    uri         %s;\n' "$1" "$2"
    if [[ -n "$ACME_EMAIL" ]]; then
        printf '    contact     %s;\n' "$ACME_EMAIL"
    fi
    printf '    state_path  %s/%s;\n    accept_terms_of_service;\n}\n\n' "$ACME_STATE" "$1"
}

{
    echo "resolver          ${WAF_RESOLVER} valid=300s;"
    echo "resolver_timeout  5s;"
    echo
    acme_issuer letsencrypt https://acme-v02.api.letsencrypt.org/directory
    acme_issuer letsencrypt_staging https://acme-staging-v02.api.letsencrypt.org/directory
} > /etc/nginx/runtime/acme.conf

install -d -o nginx -g nginx -m 0700 "$ACME_STATE" "$ACME_STATE/letsencrypt" "$ACME_STATE/letsencrypt_staging"
chown -R nginx:nginx "$ACME_STATE"

echo "entrypoint: ModSecurity ${MODSECURITY_ENGINE}, CRS paranoia ${CRS_PARANOIA_LEVEL}," \
     "anomaly thresholds ${CRS_INBOUND_ANOMALY_THRESHOLD}/${CRS_OUTBOUND_ANOMALY_THRESHOLD}," \
     "resolver ${WAF_RESOLVER}" >&2

exec "$@"

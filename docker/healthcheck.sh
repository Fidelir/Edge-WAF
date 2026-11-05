#!/bin/bash
set -euo pipefail

exec 3<>"/dev/tcp/127.0.0.1/${WAF_HEALTH_PORT:-8099}"
printf 'GET /healthz HTTP/1.0\r\nHost: localhost\r\n\r\n' >&3
IFS= read -r -t 3 status_line <&3
[[ "$status_line" == *" 200 "* ]]

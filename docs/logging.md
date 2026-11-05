# Logging

| File | Writer | Format | What is logged |
|---|---|---|---|
| `logs/access.log` | nginx | JSON, one object per line (`waf_json`, `nginx/log-json.conf`) | Every request, except 2xx/3xx responses for static assets (`.css`, `.js`, `.mjs`, images, fonts) |
| `logs/error.log` | nginx | nginx error log, level `warn` | Errors; ModSecurity `Warning` (rule matched) and `Access denied with code 403` lines |
| `logs/modsec_audit.log` | ModSecurity | JSON, one object per line | Transactions that matched a rule, or ended with 4xx (except 404) / 5xx; parts A, B, F, H (request headers, response headers, rule messages) |

Without the `logs/` mount, all three go to the container output (`docker logs waf`).

## Correlation

nginx assigns `$request_id` to every request and passes it to ModSecurity as the transaction ID and to the upstream as
the `X-Request-ID` header:

```
access.log  "request_id"               ==  modsec_audit.log  .transaction.unique_id
```

```bash
jq -c 'select(.status == "403")' logs/access.log                                       # blocked requests
jq -c --arg id "$ID" 'select(.request_id == $id)' logs/access.log                      # one request
jq -c --arg id "$ID" 'select(.transaction.unique_id == $id)' logs/modsec_audit.log     # its audit entry
```

## Access log fields

All values are strings; empty when not applicable.

| Field | nginx variable | Meaning |
|---|---|---|
| `@timestamp` | `$time_iso8601` | Request end time, ISO 8601 |
| `service`, `event` | | Constants `edge-waf`, `http.access` |
| `request_id` | `$request_id` | Unique request ID (32 hex chars) |
| `client_ip` | `$remote_addr` | Client address; the real visitor when a realip example is enabled |
| `peer_ip` | `$realip_remote_addr` | TCP peer (CDN or load balancer when realip is enabled) |
| `x_forwarded_for` | `$http_x_forwarded_for` | Incoming `X-Forwarded-For`, as sent |
| `cf_connecting_ip`, `cf_ipcountry` | `$http_cf_*` | Cloudflare headers, as sent |
| `username` | `$remote_user` | HTTP basic auth user |
| `scheme`, `request_method`, `server_protocol` | | `http`/`https`, method, `HTTP/1.1` / `HTTP/2.0` |
| `uri` | `$uri` | Decoded, normalized path |
| `request_uri` | `$request_uri` | Raw path and query string as received |
| `query_string` | `$query_string` | Raw query string |
| `http_referer`, `useragent`, `origin` | | Request headers |
| `request_length` | `$request_length` | Request size including headers, bytes |
| `request_time` | `$request_time` | Total time, seconds with ms resolution |
| `deny_probe` | `$waf_deny_probe` | `1` if the request matched the probe patterns (blocked with 403 where the site includes `deny-probes.conf`) |
| `deny_empty_ua` | `$waf_deny_empty_ua` | `1` if the request had no `User-Agent` and the client is not in `monitor-ips.conf` |
| `status` | `$status` | Response status sent to the client (403 for WAF blocks) |
| `content_length` | `$content_length` | Request `Content-Length` |
| `body_bytes_sent`, `bytes_sent` | | Response body / total bytes sent |
| `hostname` | `$host` | Requested host |
| `connection`, `connection_requests` | | Connection serial number, requests on it |
| `upstream_addr`, `upstream_status` | | Backend address and status (empty when nginx answered itself) |
| `upstream_connect_time`, `upstream_header_time`, `upstream_response_time` | | Backend timings, seconds |
| `upstream_cache_status` | | Cache status when proxy caching is configured |
| `proxy_host` | `$proxy_host` | Host from `proxy_pass` |
| `ssl_protocol`, `ssl_cipher`, `ssl_server_name` | | TLS version, cipher, SNI |
| `ssl_client_serial`, `ssl_client_fingerprint` | | Client certificate (mutual TLS only) |

## Audit log

Each line is `{"transaction": {...}}` with `client_ip`, `time_stamp`, `unique_id`, `request` (method, URI, HTTP
version, headers), `response` (status, headers), `producer` (ModSecurity, connector and CRS versions, engine mode) and
`messages`. Each message has `message` and `details` with `ruleId`, `data`, `match`, `severity`, `tags`, `file` and
`lineNumber`.

Request bodies are not written (`SecAuditLogParts ABFHZ`), but request headers are, including cookies and
`Authorization`, and `data` may quote matched parameter values: restrict access to `logs/` and set a retention period.

## Rotation

nginx and ModSecurity keep the files open, and `nginx -s reopen` does not reopen the ModSecurity audit log; rotate with
`copytruncate` on the host:

```
/opt/edge-waf/logs/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
```

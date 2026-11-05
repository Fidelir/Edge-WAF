# Tuning

Start in `DetectionOnly`, collect false positives from real traffic, exclude them as narrowly as possible, then switch to
`On`. CRS background: [false positives and tuning](https://coreruleset.org/docs/2-how-crs-works/2-3-false-positives-and-tuning/).

## Engine mode

| Scope | How |
|---|---|
| Global | `MODSECURITY_ENGINE=DetectionOnly` (default), `On` or `Off`, then `docker compose up -d` |
| One site | `modsecurity_rules 'SecRuleEngine On';` (or `DetectionOnly`) in its `server` block |
| One location | `modsecurity off;` in the `location` block (for example a webhook with signed payloads) |

Per-site and per-location settings are reloaded with `nginx -s reload`; environment changes need `docker compose up -d`.

## Paranoia level and anomaly thresholds

CRS adds up an anomaly score per request and blocks when it reaches the threshold
([anomaly scoring](https://coreruleset.org/docs/2-how-crs-works/2-1-anomaly_scoring/)).

| Variable | Default | Notes |
|---|---|---|
| `CRS_PARANOIA_LEVEL` | `1` | 1: few false positives, a good default. 2: recommended for sensitive apps after tuning. 3–4: high false positive rate, for experienced users ([paranoia levels](https://coreruleset.org/docs/2-how-crs-works/2-2-paranoia_levels/)) |
| `CRS_INBOUND_ANOMALY_THRESHOLD` | `5` | One critical rule (score 5) blocks. Raising it temporarily (e.g. to 10) is a common migration step |
| `CRS_OUTBOUND_ANOMALY_THRESHOLD` | `4` | Response inspection (data leakage, error pages) |

Allowed HTTP methods are `GET HEAD POST OPTIONS PUT PATCH DELETE` (`modsecurity/crs-setup.conf`, rule 900200).

## Finding false positives

Rules that matched most often:

```bash
jq -r '.transaction.messages[]?.details.ruleId' logs/modsec_audit.log | sort | uniq -c | sort -rn | head -20
```

Details for one rule (URI, matched data):

```bash
jq -c '.transaction | {id: .unique_id, uri: .request.uri,
       m: [.messages[] | select(.details.ruleId == "942100") | .details.data]}' logs/modsec_audit.log
```

The access log line for the same request has `"request_id"` equal to the audit log `unique_id`.

## Rule exclusions per site

Put exclusions in the site's `server` block (or a `location`) with `modsecurity_rules`, or keep them in a file and load
it with `modsecurity_rules_file`. Files under `conf.d/modsec/` are not read by nginx as configuration (the
`conf.d/*.conf` include is not recursive), so that directory is a convenient place for them.

Remove a rule for the whole site:

```nginx
modsecurity_rules 'SecRuleRemoveById 920350';
```

Stop inspecting one parameter with one rule:

```nginx
modsecurity_rules 'SecRuleUpdateTargetById 942100 "!ARGS:query"';
```

Exclude a parameter from all SQL injection rules, only for one path (runtime exclusion in phase 1; use your own rule
IDs from the 10000–99999 range):

```nginx
modsecurity_rules '
    SecRule REQUEST_URI "@beginsWith /search" "id:10001,phase:1,pass,nolog,ctl:ruleRemoveTargetByTag=attack-sqli;ARGS:q"
';
```

Prefer the narrowest exclusion that works: one parameter on one path, then one rule, then a whole location.

## CRS plugins

Application-specific exclusion packages (WordPress, Nextcloud, ...) are published as
[CRS plugins](https://coreruleset.org/docs/4-about-plugins/4-1-plugins/). Mount their files into
`/opt/owasp-crs/plugins/`; `modsecurity/main.conf` already loads `*-config.conf`, `*-before.conf` and `*-after.conf`
from there.

## Probe guard

`nginx/probes.conf` flags scanner traffic; sites enforce it with `include snippets/deny-probes.conf;`. Matching requests
get 403 before ModSecurity and the upstream see them, and are logged with `"deny_probe":"1"` in `access.log`.

- Decoded path (percent-encoding does not bypass it):
  - dotfiles and dot-directories except `/.well-known/`, `.env` files;
  - `*.php`, `*.phtml`, `*.phar`, `*.asp`, `*.aspx`;
  - backup and config files: `.bak`, `.old`, `.orig`, `.save`, `.swp`, `.sql`, `.log`, `.ini`, `.dist`, `.yml`,
    `.yaml`, `.conf`, `web.config`, `database.yml` / `.sqlite`;
  - CMS paths: `/wp-*`, `wlwmanifest.xml`, `/xmlrpc`, `acymailing`, `/joomla`, `/drupal`, `/typo3`;
  - admin and debug tools: phpMyAdmin, `/pma`, Adminer, `phpinfo`, Symfony `/_profiler` and `/_wdt`, Spring
    `/actuator`, `/jolokia`, Vite `/@fs/`;
  - exploit targets: `/proc/self/`, `/shell`, `vendor/phpunit`, `/cgi-bin/`, Apache `/server-status` and
    `/server-info`, Exchange `/autodiscover`, `/owa`, `/ecp`, router paths `/hnap1`, `/boaform`;
  - API discovery: `/graphql`, `/api/graphql`, `/api/swagger`, `/api/openapi`.
- Raw URI including the query string: path traversal (`../`, `..\` and their percent-encoded forms), `/proc/self/`,
  `rest_route=`, `UNION [ALL] SELECT`.
- User agents of scanners: sqlmap, nikto, nuclei, masscan, nmap, zgrab, gobuster, feroxbuster, dirsearch, dirbuster,
  ffuf, wfuzz, wpscan, whatweb, acunetix, netsparker, openvas, nessus, LeakIX and a few exploit kits.

Applications that use any of these paths (WordPress or other PHP without a front controller, ASP.NET, GraphQL, Swagger
UI) should not include the snippet and rely on CRS, or use an edited copy of the patterns:
`- ./my-probes.conf:/etc/nginx/probes.conf:ro` in the compose file.

`snippets/deny-empty-ua.conf` rejects requests without a `User-Agent` except from `nginx/monitor-ips.conf`. Do not use it
on APIs whose clients may omit the header.

## Request body limits

`client_max_body_size` (nginx, default `25m`, can be set per site) and `SecRequestBodyLimit` (ModSecurity, 25 MiB in
`modsecurity/modsecurity.conf`) both apply; raise both for large uploads. Bodies without files are limited to 128 KiB by
`SecRequestBodyNoFilesLimit`.

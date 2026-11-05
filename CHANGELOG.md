# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-05

First public release.

### Components

| Component | Version |
|---|---|
| nginx | 1.30.6 |
| libmodsecurity | 3.0.17 |
| ModSecurity-nginx connector | 1.0.4 |
| nginx-acme (`ngx_http_acme_module`) | 0.4.1 |
| OWASP CRS | 4.30.0 |
| Base image | `debian:trixie-slim` (Debian 13.7 at release build: OpenSSL 3.5.7, PCRE2 10.46) |

### Added

- nginx built from source with the ModSecurity-nginx connector, libmodsecurity and OWASP CRS; sources pinned by SHA-256.
- Automatic HTTPS with the official nginx ACME module: `acme_certificate letsencrypt;` in a site requests and renews
  its certificate; `letsencrypt` and `letsencrypt_staging` issuers are predefined, state is kept in `acme/`
  (`ACME_EMAIL`, `WAF_RESOLVER`).
- ModSecurity starts in `DetectionOnly`; engine mode, CRS paranoia level and anomaly thresholds are set with
  environment variables (`MODSECURITY_ENGINE`, `CRS_PARANOIA_LEVEL`, `CRS_INBOUND_ANOMALY_THRESHOLD`,
  `CRS_OUTBOUND_ANOMALY_THRESHOLD`).
- nginx-level probe guard (`snippets/deny-probes.conf`) for scanner paths, path traversal, `UNION SELECT` and scanner
  user agents; optional empty `User-Agent` guard with an allowlist (`snippets/deny-empty-ua.conf`).
- Edge defaults: requests for unknown host names are closed and TLS handshakes without a known server name are
  rejected (`conf.d/default.conf`); client timeouts against slow clients (header 10 s; body, send and keep-alive 30 s);
  TLS 1.2 and 1.3 with forward-secret AEAD ciphers and the hybrid post-quantum key exchange `X25519MLKEM768`; upstream
  `Server`, `X-Powered-By` and similar headers hidden; nginx compiled as PIE with stack protection, `FORTIFY_SOURCE`
  and full RELRO.
- Host network mode by default (`docker-compose.yml`); bridge mode with published ports (`docker-compose.bridge.yml`).
- IPv4 and IPv6 listeners in the default server and the examples.
- Examples: quick start, automatic HTTPS, TLS reverse proxy with your own certificates, static site, PHP-FPM, JSON API,
  realip for Cloudflare and generic proxies.
- JSON access log (`waf_json`), error log and ModSecurity JSON audit log in `logs/`, correlated by `request_id`.
- Container `HEALTHCHECK` on a loopback `/healthz` endpoint.
- CI: build, `nginx -t`, example validation, smoke tests, the README quick start in host mode, automatic HTTPS
  against Pebble (the Let's Encrypt test CA) including a site added by reload, shellcheck, actionlint, Trivy (also
  weekly); release workflow building without cache and publishing to GHCR with SBOM and provenance.

[Unreleased]: https://github.com/Fidelir/edge-waf/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Fidelir/edge-waf/releases/tag/v0.1.0

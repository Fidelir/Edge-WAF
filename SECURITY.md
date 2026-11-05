# Security policy

## Reporting a vulnerability

Report privately through GitHub: **Security → Report a vulnerability**
([private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)).
Do not open public issues for vulnerabilities.

Please include the release or image digest, the relevant configuration, steps to reproduce and the impact.
This is a volunteer-maintained project: we aim to acknowledge reports within 7 days and to fix confirmed issues in the
next release, without a guaranteed timeline.

## Scope

In scope: this repository — the Dockerfile, nginx and ModSecurity configuration, scripts, CI workflows and the images
published from it (for example, a default setting that exposes data or weakens TLS).

Report upstream instead:

- nginx: <https://nginx.org/en/security_advisories.html>
- nginx-acme (automatic HTTPS): <https://github.com/nginx/nginx-acme/security/policy>
- ModSecurity and the ModSecurity-nginx connector: <https://github.com/owasp-modsecurity/ModSecurity/security/policy>
- OWASP CRS, including rule bypasses: <https://github.com/coreruleset/coreruleset/security/policy>
- Debian packages in the base image: <https://www.debian.org/security/>

## What we do not promise

- Detection of every attack. A CRS bypass or false positive is not a vulnerability of this project.
- Protection against volumetric DDoS, bots or credential stuffing.
- Zero CVEs in the image. CI blocks releases with CRITICAL/HIGH vulnerabilities that have a fix available; vulnerabilities
  without an upstream fix in Debian are shipped until Debian fixes them.
- Fixes for old releases. Only the latest release is supported; upgrade to receive fixes.

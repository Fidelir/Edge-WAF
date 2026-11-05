# Contributing

Issues and pull requests are welcome. Keep changes small, documented in English, and covered by the tests below.

## Development loop

```bash
docker build -t edge-waf:local .
tests/examples.sh edge-waf:local     # nginx -t for default.conf with every examples/*.conf
tests/smoke.sh edge-waf:local        # probes, traversal, SQLi in DetectionOnly and On
tests/quickstart.sh edge-waf:local   # README quick start in host mode; uses ports 80, 443, 8080 on the Docker host
tests/acme.sh edge-waf:local         # automatic HTTPS against Pebble, the Let's Encrypt test CA
shellcheck docker/*.sh tests/*.sh scripts/*.sh
```

CI runs the same steps plus actionlint and a Trivy scan.

## Updating a pinned component

nginx, libmodsecurity, the ModSecurity-nginx connector, nginx-acme and CRS are pinned in the `Dockerfile` by version
and SHA-256.
Example for CRS (the same steps apply to the others, each with its signature file and signing key):

```bash
v=4.31.0
base=https://github.com/coreruleset/coreruleset/releases/download/v$v
curl -fsSLO "$base/coreruleset-$v-minimal.tar.gz"
curl -fsSLO "$base/coreruleset-$v-minimal.tar.gz.asc"
gpg --keyserver hkps://keys.openpgp.org --recv-keys 0x38EEACA1AB8A6E72
gpg --verify "coreruleset-$v-minimal.tar.gz.asc" "coreruleset-$v-minimal.tar.gz"
sha256sum "coreruleset-$v-minimal.tar.gz"
```

Signing keys: nginx <https://nginx.org/en/pgp_keys.html>; nginx-acme releases are signed by its maintainer,
<https://github.com/bavshin-f5.gpg> (`F824 BE52 8D85 64FB ECB8 44D4 88D8 6227 C5BF E42D`); ModSecurity and the
connector publish `.asc` files next to each release archive on GitHub. nginx-acme fetches its Rust dependencies from
crates.io at build time, pinned by its `Cargo.lock` (`--locked`). It must be built against the same nginx version, so
update both together when nginx-acme requires it.

Then update `CRS_VERSION` and `CRS_SHA256` in the `Dockerfile`, add the change to the `Unreleased` section of
`CHANGELOG.md` (with the new version in its component table), and run the tests. A CRS update can change detection:
mention notable rule changes from the CRS release notes.

## Releases

1. Move `Unreleased` entries in `CHANGELOG.md` to a new `## [X.Y.Z] - YYYY-MM-DD` section ([SemVer](https://semver.org/spec/v2.0.0.html)).
2. Update `WAF_IMAGE` defaults in the compose files and README to the new version.
3. Tag and push: `git tag vX.Y.Z && git push origin vX.Y.Z`. The release workflow tests, scans and publishes the image to
   GHCR and creates the GitHub release from the changelog section.

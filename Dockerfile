# syntax=docker/dockerfile:1

ARG NGINX_VERSION=1.30.6
ARG NGINX_SHA256=3cf46f5ed7504d460125866b7bea99fb357f31d887e2e63b35503310e9b8b6c8
ARG MODSECURITY_VERSION=3.0.17
ARG MODSECURITY_SHA256=f283b33d5c21130fd3a15c84a93a1abe12bd1949edaf44288b12af571b671a50
ARG MODSECURITY_NGINX_VERSION=1.0.4
ARG MODSECURITY_NGINX_SHA256=6bdc7570911be884c1e43aaf85046137f9fde0cfa0dd4a55b853c81c45a13313
ARG NGINX_ACME_VERSION=0.4.1
ARG NGINX_ACME_SHA256=b4f99f971bd0bebc89b2037f3afeaa3281004fe434de558df87d69cab2be1f22
ARG CRS_VERSION=4.30.0
ARG CRS_SHA256=3d678a41fd5aade34760127fef5dd64fd7a77848913fc0f70dde0cf467c94427

FROM debian:trixie-slim AS build

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl pkg-config cargo rustc libclang-dev \
        libpcre2-dev libssl-dev zlib1g-dev libxml2-dev libyajl-dev libmaxminddb-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src

# libmodsecurity v3
ARG MODSECURITY_VERSION
ARG MODSECURITY_SHA256
RUN set -eux; \
    curl -fsSL -o modsecurity.tar.gz \
        "https://github.com/owasp-modsecurity/ModSecurity/releases/download/v${MODSECURITY_VERSION}/modsecurity-v${MODSECURITY_VERSION}.tar.gz"; \
    echo "${MODSECURITY_SHA256}  modsecurity.tar.gz" | sha256sum -c -; \
    mkdir modsecurity; \
    tar -xzf modsecurity.tar.gz -C modsecurity --strip-components=1; \
    cd modsecurity; \
    ./configure --prefix=/usr/local/modsecurity --with-yajl \
        --disable-static --disable-examples --disable-doxygen-doc \
        --disable-dependency-tracking --enable-silent-rules; \
    make -j"$(nproc)"; \
    make install; \
    strip --strip-unneeded /usr/local/modsecurity/lib/libmodsecurity.so.*.*

ARG NGINX_VERSION
ARG NGINX_SHA256
ARG MODSECURITY_NGINX_VERSION
ARG MODSECURITY_NGINX_SHA256
ARG NGINX_ACME_VERSION
ARG NGINX_ACME_SHA256
RUN set -eux; \
    curl -fsSL -o nginx.tar.gz "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"; \
    echo "${NGINX_SHA256}  nginx.tar.gz" | sha256sum -c -; \
    curl -fsSL -o modsecurity-nginx.tar.gz \
        "https://github.com/owasp-modsecurity/ModSecurity-nginx/releases/download/v${MODSECURITY_NGINX_VERSION}/ModSecurity-nginx-v${MODSECURITY_NGINX_VERSION}.tar.gz"; \
    echo "${MODSECURITY_NGINX_SHA256}  modsecurity-nginx.tar.gz" | sha256sum -c -; \
    curl -fsSL -o nginx-acme.tar.gz \
        "https://github.com/nginx/nginx-acme/releases/download/v${NGINX_ACME_VERSION}/nginx-acme-${NGINX_ACME_VERSION}.tar.gz"; \
    echo "${NGINX_ACME_SHA256}  nginx-acme.tar.gz" | sha256sum -c -; \
    mkdir nginx modsecurity-nginx nginx-acme; \
    tar -xzf nginx.tar.gz -C nginx --strip-components=1; \
    tar -xzf modsecurity-nginx.tar.gz -C modsecurity-nginx --strip-components=1; \
    tar -xzf nginx-acme.tar.gz -C nginx-acme --strip-components=1; \
    cd nginx; \
    NGX_RUSTC_OPT=--locked ./configure \
        --prefix=/etc/nginx \
        --sbin-path=/usr/sbin/nginx \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --pid-path=/run/nginx.pid \
        --lock-path=/run/nginx.lock \
        --http-client-body-temp-path=/var/cache/nginx/client_temp \
        --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
        --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
        --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
        --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
        --user=nginx --group=nginx \
        --with-compat --with-threads --with-file-aio --with-pcre-jit \
        --with-http_ssl_module --with-http_v2_module --with-http_v3_module \
        --with-http_realip_module --with-http_auth_request_module --with-http_sub_module \
        --with-http_gunzip_module --with-http_gzip_static_module --with-http_stub_status_module \
        --with-http_secure_link_module --with-http_slice_module \
        --with-stream --with-stream_ssl_module --with-stream_ssl_preread_module --with-stream_realip_module \
        --with-cc-opt='-O2 -fstack-protector-strong -Wformat -Werror=format-security -D_FORTIFY_SOURCE=2 -fPIC' \
        --with-ld-opt='-Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie' \
        --add-module=/usr/src/modsecurity-nginx \
        --add-dynamic-module=/usr/src/nginx-acme; \
    make -j"$(nproc)"; \
    make install; \
    strip /usr/sbin/nginx; \
    strip --strip-unneeded /etc/nginx/modules/ngx_http_acme_module.so

# OWASP Core Rule Set
ARG CRS_VERSION
ARG CRS_SHA256
RUN set -eux; \
    curl -fsSL -o crs.tar.gz \
        "https://github.com/coreruleset/coreruleset/releases/download/v${CRS_VERSION}/coreruleset-${CRS_VERSION}-minimal.tar.gz"; \
    echo "${CRS_SHA256}  crs.tar.gz" | sha256sum -c -; \
    mkdir -p /opt/owasp-crs; \
    tar -xzf crs.tar.gz -C /opt/owasp-crs --strip-components=1; \
    rm -rf /opt/owasp-crs/docs


FROM debian:trixie-slim

ARG NGINX_VERSION
ARG MODSECURITY_VERSION
ARG MODSECURITY_NGINX_VERSION
ARG NGINX_ACME_VERSION
ARG CRS_VERSION

LABEL org.opencontainers.image.title="edge-waf" \
      org.opencontainers.image.description="nginx + ModSecurity v3 + OWASP CRS reverse proxy WAF with automatic HTTPS" \
      org.opencontainers.image.licenses="Apache-2.0" \
      edge-waf.nginx.version="${NGINX_VERSION}" \
      edge-waf.modsecurity.version="${MODSECURITY_VERSION}" \
      edge-waf.modsecurity-nginx.version="${MODSECURITY_NGINX_VERSION}" \
      edge-waf.nginx-acme.version="${NGINX_ACME_VERSION}" \
      edge-waf.crs.version="${CRS_VERSION}"

ENV MODSECURITY_ENGINE=DetectionOnly \
    CRS_PARANOIA_LEVEL=1 \
    CRS_INBOUND_ANOMALY_THRESHOLD=5 \
    CRS_OUTBOUND_ANOMALY_THRESHOLD=4 \
    WAF_HEALTH_PORT=8099

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates libpcre2-8-0 libssl3t64 zlib1g libxml2 libyajl2 libmaxminddb0; \
    apt-get upgrade -y --no-install-recommends; \
    rm -rf /var/lib/apt/lists/*; \
    groupadd --system --gid 101 nginx; \
    useradd --system --uid 101 --gid nginx --no-create-home --home-dir /nonexistent \
        --shell /usr/sbin/nologin nginx

COPY --from=build /usr/local/modsecurity/lib/ /usr/local/modsecurity/lib/
COPY --from=build /usr/sbin/nginx /usr/sbin/nginx
COPY --from=build /etc/nginx/modules/ /etc/nginx/modules/
COPY --from=build /etc/nginx/mime.types /etc/nginx/fastcgi_params /etc/nginx/fastcgi.conf \
                  /etc/nginx/scgi_params /etc/nginx/uwsgi_params /etc/nginx/
COPY --from=build /opt/owasp-crs/ /opt/owasp-crs/
COPY --from=build /usr/src/modsecurity/unicode.mapping /etc/nginx/modsec/unicode.mapping

RUN set -eux; \
    mkdir -p /etc/nginx/conf.d /etc/nginx/ssl.d /etc/nginx/runtime /var/cache/nginx /var/log/nginx; \
    chown nginx:nginx /var/cache/nginx; \
    install -d -o nginx -g nginx -m 0700 /var/lib/nginx/acme; \
    ln -sf /dev/stdout /var/log/nginx/access.log; \
    ln -sf /dev/stderr /var/log/nginx/error.log; \
    ln -sf /dev/stdout /var/log/nginx/modsec_audit.log

COPY nginx/ /etc/nginx/
COPY modsecurity/ /etc/nginx/modsec/
COPY --chmod=0755 docker/entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY --chmod=0755 docker/healthcheck.sh /usr/local/bin/healthcheck

# nginx -t generates ACME account keys; they must not be shipped in the image.
RUN docker-entrypoint.sh nginx -t && rm -rf /var/lib/nginx/acme/*

EXPOSE 80 443
STOPSIGNAL SIGQUIT
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --start-interval=2s --retries=3 CMD ["healthcheck"]
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]

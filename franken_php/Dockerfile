FROM dunglas/frankenphp:1.11.1-php8.4 AS builder

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        $PHPIZE_DEPS \
        libavif-dev \
        libfreetype6-dev \
        libmagickwand-dev \
        libjpeg-dev \
        libmemcached-dev \
        libpq-dev \
        libpng-dev \
        libwebp-dev \
        libzip-dev

RUN docker-php-ext-configure gd \
        --with-freetype --with-jpeg --with-avif --with-webp \
    && docker-php-ext-configure intl \
    && docker-php-ext-install -j"$(nproc)" \
        bcmath \
        calendar \
        exif \
        gd \
        intl \
        mysqli \
        pdo \
        pdo_mysql \
        pdo_pgsql \
        pcntl \
        zip

RUN pecl install apcu igbinary imagick redis xdebug \
    && docker-php-ext-enable apcu igbinary imagick redis xdebug \
    && pecl clear-cache

FROM composer:2 AS composer-stage

FROM debian:trixie-slim

ARG UID=1000
ARG GID=1000
ARG APP_USER=www
ARG WORKDIR=/var/www
ARG SUPERCRONIC_VERSION=v0.2.38
ARG FD_VERSION=10.3.0
ARG FZF_VERSION=0.67.0

COPY --from=builder /usr/local/bin/frankenphp    /usr/local/bin/frankenphp
COPY --from=builder /usr/local/bin/php           /usr/local/bin/php
COPY --from=builder /usr/local/bin/php-cgi       /usr/local/bin/php-cgi
COPY --from=builder /usr/local/bin/phar.phar     /usr/local/bin/phar.phar
COPY --from=builder /usr/local/bin/phpize        /usr/local/bin/phpize
COPY --from=builder /usr/local/bin/php-config    /usr/local/bin/php-config
COPY --from=builder /usr/local/bin/docker-php-entrypoint  /usr/local/bin/docker-php-entrypoint
COPY --from=builder /usr/local/bin/docker-php-ext-configure /usr/local/bin/docker-php-ext-configure
COPY --from=builder /usr/local/bin/docker-php-ext-enable    /usr/local/bin/docker-php-ext-enable
COPY --from=builder /usr/local/bin/docker-php-ext-install   /usr/local/bin/docker-php-ext-install
COPY --from=builder /usr/local/lib/libphp.so     /usr/local/lib/libphp.so
COPY --from=builder /usr/local/lib/libwatcher-c.so.0 /usr/local/lib/libwatcher-c.so.0
COPY --from=builder /usr/local/lib/php/          /usr/local/lib/php/
COPY --from=builder /usr/local/etc/php/          /usr/local/etc/php/
COPY --from=builder /data/caddy                  /data/caddy
COPY --from=builder /config/caddy                /config/caddy
COPY --from=builder /etc/caddy/                  /etc/caddy/
COPY --from=composer-stage /usr/bin/composer      /usr/local/bin/composer

RUN ln -s phar.phar /usr/local/bin/phar \
    && ldconfig

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        libargon2-1 \
        libavif16 \
        libcurl4t64 \
        libfreetype6 \
        libicu76 \
        libjpeg62-turbo \
        libmagickwand-7.q16-10 \
        libmemcached11t64 \
        libonig5 \
        libpng16-16t64 \
        libpq5 \
        libreadline8t64 \
        libsodium23 \
        libsqlite3-0 \
        libssl3t64 \
        libwebp7 \
        libxml2 \
        libzip5 \
        xfonts-75dpi \
        fontconfig \
        libx11-6 \
        libxcb1 \
        libxext6 \
        libxrender1 \
        xfonts-base \
        zlib1g \
        curl \
        fish \
        libcap2-bin \
        git \
        jpegoptim \
        optipng \
        pngquant \
        ripgrep \
        ssh \
        sudo \
        unzip \
        xz-utils \
    && ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL "https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_${ARCH}.deb" \
        -o /tmp/wkhtmltox.deb \
    && dpkg --force-depends -i /tmp/wkhtmltox.deb \
    && rm -f /usr/local/bin/wkhtmltoimage /usr/local/lib/libwkhtmltox.so* \
    && curl -fsSL "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-${ARCH}" \
        -o /usr/local/bin/supercronic \
    && chmod 0755 /usr/local/bin/supercronic \
    && curl -fsSL "https://github.com/sharkdp/fd/releases/download/v${FD_VERSION}/fd-musl_${FD_VERSION}_${ARCH}.deb" \
        -o /tmp/fd.deb \
    && dpkg -i /tmp/fd.deb \
    && curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_${ARCH}.tar.gz" \
        -o /tmp/fzf.tgz \
    && tar -xf /tmp/fzf.tgz -C /usr/local/bin \
    && chmod 0755 /usr/local/bin/fzf \
    && rm -rf /tmp/* /var/tmp/* /usr/share/doc/* /usr/share/man/* \
    && (groupadd -g "${GID}" "${APP_USER}" || true) \
    && useradd -m -u "${UID}" -g "${GID}" -s /bin/bash "${APP_USER}" \
    && setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp \
    && chown -R "${UID}:${GID}" /data/caddy /config/caddy \
    && mkdir -p /etc/sudoers.d \
    && echo "${APP_USER} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${APP_USER}" \
    && chmod 0440 "/etc/sudoers.d/${APP_USER}" \
    && echo "Set disable_coredump false" > /etc/sudo.conf

ENV PHP_INI_DIR=/usr/local/etc/php \
    GODEBUG=cgocheck=0 \
    APP_USER=${APP_USER} \
    XDG_DATA_HOME=/home/${APP_USER}/.local/share \
    XDG_CONFIG_HOME=/home/${APP_USER}/.config \
    XDG_CACHE_HOME=/home/${APP_USER}/.cache \
    WORKDIR=${WORKDIR}
ENV PATH=/home/${APP_USER}/.bun/bin:/home/${APP_USER}/.local/bin:${PATH}

COPY --link conf.d/  /usr/local/etc/php/conf.d/
COPY --link php-env.sh entrypoint.sh /usr/local/bin/

USER ${UID}:${GID}

RUN set -eux; \
    mkdir -p "$HOME/.local/bin" && touch "$HOME/.env-vars" \
    && ARCH="$(dpkg --print-architecture)" \
    && case "$ARCH" in amd64) NODE_ARCH=x64;; arm64) NODE_ARCH=arm64;; esac \
    && NODE_VERSION=$(curl -fsSL https://resolve-node.now.sh/lts) \
    && curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" \
        | tar -xJ --strip-components=1 -C "$HOME/.local" \
    && npm install -g npm@latest \
    && npm config set update-notifier false \
    && curl -fsSL https://bun.com/install | bash \
    && rm -rf "$HOME/.local/include" \
             "$HOME/.local/CHANGELOG.md" \
             "$HOME/.local/README.md" \
             "$HOME/.npm" \
             "$HOME/.cache" \
             "$HOME/.bun/install"

WORKDIR ${WORKDIR}
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

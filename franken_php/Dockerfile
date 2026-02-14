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

FROM dunglas/frankenphp:1.11.1-php8.4

ARG UID=1000
ARG GID=1000
ARG APP_USER=www
ARG WORKDIR=/var/www
ARG SUPERCRONIC_VERSION=v0.2.38
ARG FD_VERSION=10.3.0
ARG FZF_VERSION=0.67.0

COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=builder /usr/local/etc/php/conf.d/     /usr/local/etc/php/conf.d/
COPY --from=composer-stage /usr/bin/composer        /usr/local/bin/composer

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        libavif16 \
        libfreetype6 \
        libmagickwand-7.q16hdri-10 \
        libjpeg62-turbo \
        libmemcached11t64 \
        libpq5 \
        libpng16-16t64 \
        libwebp7 \
        libzip5 \
        libicu76 \
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
        git \
        imagemagick \
        jpegoptim \
        optipng \
        pngquant \
        ripgrep \
        ssh \
        sudo \
        unzip \
    && ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL "https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_${ARCH}.deb" \
        -o /tmp/wkhtmltox.deb \
    && dpkg --force-depends -i /tmp/wkhtmltox.deb \
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
    && rm -rf /tmp/* /var/tmp/*

RUN set -eux; \
    groupadd -g "${GID}" "${APP_USER}" || true; \
    useradd -m -u "${UID}" -g "${GID}" -s /bin/bash "${APP_USER}"; \
    setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp; \
    chown -R "${UID}:${GID}" /data/caddy /config/caddy; \
    mkdir -p /etc/sudoers.d; \
    echo "${APP_USER} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${APP_USER}"; \
    chmod 0440 "/etc/sudoers.d/${APP_USER}"; \
    echo "Set disable_coredump false" > /etc/sudo.conf

ENV APP_USER=${APP_USER} \
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
    && curl -fsSL https://bun.com/install | bash

WORKDIR ${WORKDIR}
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

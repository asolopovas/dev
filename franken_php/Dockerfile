###############################################################################
# Stage 1 — build PHP extensions that need -dev headers / build tools
###############################################################################
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

# PHP core extensions (mbstring, xml, pdo_sqlite already in base image)
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

# PECL extensions
RUN pecl install apcu igbinary imagick redis xdebug \
    && docker-php-ext-enable apcu igbinary imagick redis xdebug \
    && pecl clear-cache

###############################################################################
# Stage 2 — final slim runtime image
###############################################################################
FROM dunglas/frankenphp:1.11.1-php8.4

ARG UID=1000
ARG GID=1000
ARG APP_USER=app
ARG WORKDIR=/var/www

# Copy compiled extensions from builder
COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=builder /usr/local/etc/php/conf.d/     /usr/local/etc/php/conf.d/

# Runtime libraries + tools (single layer, no -dev packages, clean at end)
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
        wget \
    && rm -rf /tmp/* /var/tmp/*

# wkhtmltopdf (bookworm .deb needs --force-depends on Trixie due to t64 renames)
RUN ARCH="$(dpkg --print-architecture)" \
    && apt-get update -qq \
    && apt-get install -y --no-install-recommends \
        fontconfig libx11-6 libxcb1 libxext6 libxrender1 xfonts-base zlib1g \
    && wget -q "https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_${ARCH}.deb" \
        -O /tmp/wkhtmltox.deb \
    && dpkg --force-depends -i /tmp/wkhtmltox.deb \
    && rm -f /tmp/wkhtmltox.deb

# Supercronic (cron replacement designed for containers)
ARG SUPERCRONIC_VERSION=v0.2.38
RUN ARCH="$(dpkg --print-architecture)" \
    && case "$ARCH" in \
        amd64) SUPERCRONIC_ARCH=amd64 ;; \
        arm64) SUPERCRONIC_ARCH=arm64 ;; \
        *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; \
    esac \
    && wget -q "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-${SUPERCRONIC_ARCH}" \
        -O /usr/local/bin/supercronic \
    && chmod 0755 /usr/local/bin/supercronic

# User configuration
RUN set -eux; \
    groupadd -g "${GID}" "${APP_USER}" || true; \
    useradd -m -u "${UID}" -g "${GID}" -s /bin/bash "${APP_USER}"; \
    setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp; \
    chown -R "${UID}:${GID}" /data/caddy /config/caddy; \
    mkdir -p /etc/sudoers.d; \
    echo "${APP_USER} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${APP_USER}"; \
    chmod 0440 "/etc/sudoers.d/${APP_USER}"; \
    echo "Set disable_coredump false" > /etc/sudo.conf

# Environment
ENV APP_USER=${APP_USER} \
    VOLTA_HOME=/home/${APP_USER}/.volta \
    XDG_DATA_HOME=/home/${APP_USER}/.local/share \
    XDG_CONFIG_HOME=/home/${APP_USER}/.config \
    XDG_CACHE_HOME=/home/${APP_USER}/.cache \
    WORKDIR=${WORKDIR}
ENV PATH=${VOLTA_HOME}/bin:/home/${APP_USER}/.bun/bin:/home/${APP_USER}/.local/bin:${PATH}

# Config files (before switching user for correct ownership)
COPY --link conf.d/  /usr/local/etc/php/conf.d/
COPY --link php-env.sh entrypoint.sh /usr/local/bin/

# Switch to non-root user
USER ${UID}:${GID}

# User-space tool versions (declared here to preserve layer cache)
ARG VOLTA_VERSION=2.0.2
ARG NODE_VERSION=22.16.0
ARG NPM_VERSION=11.7
ARG FD_VERSION=10.3.0
ARG FZF_VERSION=0.67.0

# User-space tools
RUN mkdir -p "$HOME/.local/bin" && touch "$HOME/.env-vars"

# Volta + Node
RUN curl -fsSL https://get.volta.sh | bash -s -- --version "${VOLTA_VERSION}" --skip-setup \
    && "$HOME/.volta/bin/volta" install "node@${NODE_VERSION}" "npm@${NPM_VERSION}"

# Bun
RUN curl -fsSL https://bun.com/install | bash

# Composer (with signature verification)
RUN set -eux; \
    cd /tmp; \
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"; \
    php -r "copy('https://composer.github.io/installer.sig', 'composer-setup.sig');"; \
    php -r "\$sig = trim(file_get_contents('composer-setup.sig')); \
            if (hash_file('sha384', 'composer-setup.php') !== \$sig) { \
              unlink('composer-setup.php'); \
              fwrite(STDERR, 'ERROR: Invalid installer signature'.PHP_EOL); \
              exit(1); \
            }"; \
    php composer-setup.php --install-dir="$HOME/.local/bin" --filename=composer; \
    rm -f composer-setup.php composer-setup.sig; \
    composer --version

# fd
RUN ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL "https://github.com/sharkdp/fd/releases/download/v${FD_VERSION}/fd-musl_${FD_VERSION}_${ARCH}.deb" \
        -o /tmp/fd.deb \
    && sudo dpkg -i /tmp/fd.deb \
    && rm -f /tmp/fd.deb

# fzf
RUN ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_${ARCH}.tar.gz" \
        -o /tmp/fzf.tgz \
    && tar -xf /tmp/fzf.tgz -C /tmp \
    && install -m 0755 /tmp/fzf "$HOME/.local/bin/fzf" \
    && rm -f /tmp/fzf.tgz /tmp/fzf

WORKDIR ${WORKDIR}
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

FROM dunglas/frankenphp:1.11.1-builder-php8.4

# Build args
ARG UID=1000
ARG GID=1000
ARG APP_USER=app
ARG WORKDIR=/var/www

# System packages
RUN apt-get update && apt-get install -y --no-install-recommends \
        # PHP extension build deps
        libavif-dev \
        libfreetype6-dev \
        libmagickwand-dev \
        libjpeg-dev \
        libmemcached-dev \
        libpq-dev \
        libpng-dev \
        libwebp-dev \
        libzip-dev \
        # Runtime tools
        curl \
        ffmpeg \
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
        xfonts-75dpi

# PHP core extensions
RUN docker-php-ext-configure gd \
        --with-freetype --with-jpeg --with-avif --with-webp \
    && docker-php-ext-configure intl \
    && docker-php-ext-install -j"$(nproc)" \
        bcmath \
        calendar \
        exif \
        gd \
        intl \
        mbstring \
        mysqli \
        pdo \
        pdo_mysql \
        pdo_pgsql \
        pdo_sqlite \
        pcntl \
        xml \
        zip

# PECL extensions
RUN pecl install apcu igbinary imagick redis xdebug \
    && docker-php-ext-enable apcu igbinary imagick redis xdebug \
    && pecl clear-cache

# wkhtmltopdf
RUN ARCH="$(dpkg --print-architecture)" \
    && wget -q "https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_${ARCH}.deb" \
        -O /tmp/wkhtmltox.deb \
    && (dpkg -i /tmp/wkhtmltox.deb || apt-get install -f -y --no-install-recommends) \
    && rm -f /tmp/wkhtmltox.deb

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
ENV PATH=${VOLTA_HOME}/bin:/home/${APP_USER}/.local/bin:${PATH}

# Config files (before switching user for correct ownership)
COPY conf.d/  /usr/local/etc/php/conf.d/
COPY php-env.sh entrypoint.sh /usr/local/bin/

# Switch to non-root user
USER ${UID}:${GID}

# User-space tool versions (declared here to preserve layer cache)
ARG NODE_VERSION=24.13.0
ARG NPM_VERSION=11.7
ARG FD_VERSION=10.3.0
ARG FZF_VERSION=0.67.0

# User-space tools
RUN mkdir -p "$HOME/.local/bin" && touch "$HOME/.env-vars"

# Volta + Node
RUN curl -fsSL https://get.volta.sh | bash \
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
RUN curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_amd64.tar.gz" \
        -o /tmp/fzf.tgz \
    && tar -xf /tmp/fzf.tgz -C /tmp \
    && install -m 0755 /tmp/fzf "$HOME/.local/bin/fzf" \
    && rm -f /tmp/fzf.tgz /tmp/fzf

WORKDIR ${WORKDIR}
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

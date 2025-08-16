FROM dunglas/frankenphp:1.7.0-builder-php8.3.22
RUN apt-get update && apt-get install -y \
    libavif-dev \
    libfreetype6-dev \
    libmagickwand-dev \
    libjpeg-dev \
    libmemcached-dev \
    libpq-dev \
    libpng-dev \
    libwebp-dev \
    libzip-dev

RUN docker-php-ext-install \
    bcmath \
    calendar \
    exif \
    mbstring \
    mysqli \
    pdo \
    pdo_mysql \
    pdo_pgsql \
    pdo_sqlite \
    pcntl \
    xml \
    zip

RUN docker-php-ext-configure intl && docker-php-ext-install intl && docker-php-ext-enable intl

RUN docker-php-ext-configure gd \
    --with-freetype \
    --with-jpeg \
    --with-avif \
    --with-webp

RUN docker-php-ext-install gd

# Install PECL and PEAR extensions
RUN pecl install imagick && docker-php-ext-enable imagick
RUN pecl install xdebug && docker-php-ext-enable xdebug
RUN pecl install redis && docker-php-ext-enable redis
RUN pecl install apcu && docker-php-ext-enable apcu
RUN pecl install igbinary && docker-php-ext-enable igbinary

# Additional Software
RUN apt-get install -y \
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

RUN wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_amd64.deb \
    && dpkg -i wkhtmltox_0.12.6.1-3.bookworm_amd64.deb || apt-get install -f -y \
    && rm wkhtmltox_0.12.6.1-3.bookworm_amd64.deb

ARG UID=1000
ARG GID=1000
ARG APP_USER=app
ENV APP_USER=${APP_USER}

# User configuration
RUN groupadd -g ${GID} ${APP_USER} || true; \
    useradd -m -u ${UID} -g ${GID} -s /bin/bash ${APP_USER}; \
    setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp; \
    chown -R ${UID}:${GID} /data/caddy /config/caddy

RUN mkdir /etc/sudoers.d; \
    echo "$APP_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${APP_USER}; \
    chmod 0440 /etc/sudoers.d/${APP_USER}; \
    echo "Set disable_coredump false" > /etc/sudo.conf

ENV VOLTA_HOME=/home/${APP_USER}/.volta
ENV PATH=$VOLTA_HOME/bin:/home/${APP_USER}/.local/bin:$PATH
ENV XDG_DATA_HOME=/home/${APP_USER}/.local/share
ENV XDG_CONFIG_HOME=/home/${APP_USER}/.config
ENV XDG_CACHE_HOME=/home/${APP_USER}/.cache

COPY conf.d/  /usr/local/etc/php/conf.d/
COPY php-env.sh entrypoint.sh /usr/local/bin/


USER ${UID}:${GID}
ENV WORKDIR=/var/www

RUN touch ${HOME}/.env-vars

RUN curl https://get.volta.sh | bash
RUN volta install node@22 npm@11.5
RUN curl -fsSL https://bun.com/install | bash # for macOS, Linux, and WSL

RUN set -eux; \
    mkdir -p /home/${APP_USER}/.local/bin; \
    cd /tmp; \
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"; \
    php -r "copy('https://composer.github.io/installer.sig', 'composer-setup.sig');"; \
    php -r "\$sig = trim(file_get_contents('composer-setup.sig')); \
            if (hash_file('sha384', 'composer-setup.php') !== \$sig) { \
              unlink('composer-setup.php'); \
              fwrite(STDERR, 'ERROR: Invalid installer signature'.PHP_EOL); \
              exit(1); \
            }"; \
    php composer-setup.php --install-dir=/home/${APP_USER}/.local/bin --filename=composer; \
    php -r "unlink('composer-setup.php'); unlink('composer-setup.sig');"; \
    composer --version

# Install fd
RUN VER="10.2.0" \
 && FILE="fd-musl_${VER}_amd64.deb" \
 && URL="https://github.com/sharkdp/fd/releases/download/v${VER}/${FILE}" \
 && curl -fsSL "$URL" -o "/tmp/${FILE}" \
 && sudo dpkg -i "/tmp/${FILE}" \
 && rm -f "/tmp/${FILE}"

 # Install fzf
RUN VER="0.65.1" \
 && mkdir -p "$HOME/.local/bin" \
 && curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${VER}/fzf-${VER}-linux_amd64.tar.gz" -o /tmp/fzf.tgz \
 && tar -xf /tmp/fzf.tgz -C /tmp \
 && install -m 0755 /tmp/fzf "$HOME/.local/bin/fzf" \
 && rm -f /tmp/fzf.tgz /tmp/fzf

WORKDIR ${WORKDIR}
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

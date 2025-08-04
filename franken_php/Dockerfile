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
    git \
    unzip \
    curl \
    sudo \
    wget \
    fish \
    wkhtmltopdf \
    ffmpeg \
    imagemagick \
    optipng \
    pngquant \
    ripgrep \
    jpegoptim

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
ENV PATH=$VOLTA_HOME/bin:$PATH
ENV XDG_DATA_HOME=/home/${APP_USER}/.local/share
ENV XDG_CONFIG_HOME=/home/${APP_USER}/.config
ENV XDG_CACHE_HOME=/home/${APP_USER}/.cache

COPY conf.d/  /usr/local/etc/php/conf.d/
COPY php-env.sh entrypoint.sh /usr/local/bin/

USER ${UID}:${GID}
ENV WORKDIR=/var/www

RUN NODE_VERSION=${NODE_VERSION} bash -c "$(curl -fsSLH 'Cache-Control: no-cache' http://raw.githubusercontent.com/asolopovas/dotfiles/master/init.sh)"

RUN npm install -g @anthropic-ai/claude-code

WORKDIR ${WORKDIR}
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

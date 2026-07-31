FROM ghcr.io/mlocati/php-extension-installer:2.11.12@sha256:b6d3fa381b9ba5cf051117c1c601d6a523b590e534bf3d56eb4fbe352949c138 AS php_extension_installer

FROM composer:2.10.2@sha256:629d4ef35e75349d452851637d37a40ac33a09d6ac010139020603d79713d9bf AS composer

FROM oven/bun:1.3.14@sha256:e10577f0db68676a7024391c6e5cb4b879ebd17188ab750cf10024a6d700e5c4 AS bun

FROM dunglas/frankenphp:1.12.6-php8.4-trixie@sha256:58c4cdad00b1fe45b044a526aacd385d38228b033b05d0aca9becd8a4effc3bc AS php

COPY --from=php_extension_installer /usr/bin/install-php-extensions /usr/local/bin/

RUN IPE_SAVE_PERMDEPS_TO=/tmp/php-runtime-packages install-php-extensions \
        apcu-5.1.28 \
        bcmath \
        calendar \
        exif \
        gd \
        igbinary-3.2.16 \
        imagick-3.8.1 \
        intl \
        mysqli \
        pcntl \
        pdo_mysql \
        pdo_pgsql \
        redis-6.3.0 \
        xdebug-3.5.3 \
        zip

COPY --from=composer /usr/bin/composer /usr/local/bin/composer

RUN rm -rf \
        /usr/local/bin/docker-php-ext-configure \
        /usr/local/bin/docker-php-ext-enable \
        /usr/local/bin/docker-php-ext-install \
        /usr/local/bin/docker-php-source \
        /usr/local/bin/install-php-extensions \
        /usr/local/bin/pear \
        /usr/local/bin/peardev \
        /usr/local/bin/pecl \
        /usr/local/bin/php-config \
        /usr/local/bin/phpdbg \
        /usr/local/bin/phpize \
        /usr/local/etc/pear.conf \
        /usr/local/include \
        /usr/local/lib/php/build \
        /usr/local/lib/*.a \
        /usr/local/php

FROM debian:trixie-slim@sha256:020c0d20b9880058cbe785a9db107156c3c75c2ac944a6aa7ab59f2add76a7bd

ARG UID=1000
ARG GID=1000
ARG APP_USER=www
ARG WORKDIR=/var/www
ARG SUPERCRONIC_VERSION=v0.2.48
ARG SUPERCRONIC_SHA256=88c1b66b94c486f972fdd1a4d1f901e3e75ff04f749cddd60c5db573e3a33c6c
ARG FD_VERSION=10.4.2
ARG FD_SHA256=a8d10259388c32f9aafd65fb65b6e3e2d2782043bed687112f50e2c4cf000c27
ARG FZF_VERSION=0.74.1
ARG FZF_SHA256=df53438be5f51e151bb4044d78fda72bdfe209e3ecd2baecae48e8dea370c81b
ARG NODE_VERSION=24.16.0
ARG NODE_SHA256=d804845d34eddc21dc1092b519d643ef40b1f58ec5dec5c22b1f4bd8fabde6c9
ARG NPM_VERSION=12.0.2
ARG NPM_SHA512=b885e890b9418fa1693544d05f53e64f9a73ec194837d4258b15fecdd692347b1dd2a517b1b0cbaf9d31cd8e92c3b70956bd2ecc72833a57b4b3098f5bfa7943
ARG NPM_BRACE_EXPANSION_VERSION=5.0.8
ARG NPM_BRACE_EXPANSION_SHA512=259c83caadc3e005227ca4cf381ec310b7fa5ec07759d3ee3710ada1bd6f1573ec49785d0221c1589fed27c1c073d687f3804afb924564b36424ac771bd93342
ARG WKHTMLTOX_VERSION=0.13.0-1
ARG WKHTMLTOX_SHA256=c0f9dc53987248e3a24214b0acbee9cfc646a35837942a397ee6a533470350de
ARG TARGETARCH

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

RUN if [[ "${TARGETARCH}" != "amd64" ]]; then echo "unsupported architecture: ${TARGETARCH}; wkhtmltox is only published for amd64" >&2; exit 1; fi

COPY --link --from=php /usr/local/ /usr/local/
COPY --link --from=php /data/ /data/
COPY --link --from=php /config/ /config/
COPY --link --from=php /etc/caddy/ /etc/caddy/
COPY --from=php /tmp/php-runtime-packages /php-runtime-packages
COPY --link --from=bun /usr/local/bin/bun /usr/local/bin/bun
COPY --link --from=bun /usr/local/bin/bunx /usr/local/bin/bunx

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    export DEBIAN_FRONTEND=noninteractive \
    && apt-get -o Acquire::Retries=5 update \
    && apt-get -o Acquire::Retries=5 install -y --no-install-recommends \
        ca-certificates \
        curl \
        fish \
        fontconfig \
        git \
        libargon2-1 \
        libcap2-bin \
        libonig5 \
        libsodium23 \
        openssh-client \
        ripgrep \
        sudo \
        unzip \
        xfonts-75dpi \
        xfonts-base \
        xz-utils \
        $(cat /php-runtime-packages) \
    && rm -f /php-runtime-packages \
    && rm -rf /usr/share/doc/* /usr/share/man/*

RUN curl -fsSL --retry 5 --retry-all-errors --connect-timeout 15 \
        "https://github.com/asolopovas/wkhtmltopdf/releases/download/latest/wkhtmltox_${WKHTMLTOX_VERSION}.linux_amd64.deb" \
        -o /tmp/wkhtmltox.deb \
    && echo "${WKHTMLTOX_SHA256}  /tmp/wkhtmltox.deb" | sha256sum -c - \
    && dpkg -i /tmp/wkhtmltox.deb \
    && curl -fsSL --retry 5 --retry-all-errors --connect-timeout 15 \
        "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-amd64" \
        -o /usr/local/bin/supercronic \
    && echo "${SUPERCRONIC_SHA256}  /usr/local/bin/supercronic" | sha256sum -c - \
    && chmod 0755 /usr/local/bin/supercronic \
    && curl -fsSL --retry 5 --retry-all-errors --connect-timeout 15 \
        "https://github.com/sharkdp/fd/releases/download/v${FD_VERSION}/fd-musl_${FD_VERSION}_amd64.deb" \
        -o /tmp/fd.deb \
    && echo "${FD_SHA256}  /tmp/fd.deb" | sha256sum -c - \
    && dpkg -i /tmp/fd.deb \
    && curl -fsSL --retry 5 --retry-all-errors --connect-timeout 15 \
        "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_amd64.tar.gz" \
        -o /tmp/fzf.tgz \
    && echo "${FZF_SHA256}  /tmp/fzf.tgz" | sha256sum -c - \
    && tar -xzf /tmp/fzf.tgz -C /usr/local/bin \
    && chmod 0755 /usr/local/bin/fzf \
    && rm -rf /tmp/* /var/tmp/*

RUN if ! getent group "${GID}" >/dev/null; then groupadd --gid "${GID}" "${APP_USER}"; fi \
    && useradd --no-log-init --create-home --uid "${UID}" --gid "${GID}" --shell /bin/bash "${APP_USER}" \
    && setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp \
    && chown -R "${UID}:${GID}" /data /config \
    && echo "${APP_USER} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${APP_USER}" \
    && chmod 0440 "/etc/sudoers.d/${APP_USER}" \
    && echo "Set disable_coredump false" > /etc/sudo.conf \
    && mkdir -p "${WORKDIR}/xdebug" \
    && touch "${WORKDIR}/access.log" \
    && chown -R "${UID}:${GID}" "${WORKDIR}"

ENV PHP_INI_DIR=/usr/local/etc/php \
    GODEBUG=cgocheck=0 \
    APP_USER=${APP_USER} \
    HOME=/home/${APP_USER} \
    XDG_DATA_HOME=/home/${APP_USER}/.local/share \
    XDG_CONFIG_HOME=/home/${APP_USER}/.config \
    XDG_CACHE_HOME=/home/${APP_USER}/.cache \
    WORKDIR=${WORKDIR}
ENV PATH=/home/${APP_USER}/.local/bin:${PATH}

COPY --link conf.d/ /usr/local/etc/php/conf.d/
COPY --link --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh

RUN cp /usr/local/etc/php/php.ini-development /usr/local/etc/php/php.ini

USER ${UID}:${GID}

RUN mkdir -p "${HOME}/.local/bin" \
    && touch "${HOME}/.env-vars" \
    && curl -fsSL --retry 5 --retry-all-errors --connect-timeout 15 \
        "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
        -o /tmp/node.tar.xz \
    && echo "${NODE_SHA256}  /tmp/node.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/node.tar.xz --strip-components=1 -C "${HOME}/.local" \
    && curl -fsSL --retry 5 --retry-all-errors --connect-timeout 15 \
        "https://registry.npmjs.org/npm/-/npm-${NPM_VERSION}.tgz" \
        -o /tmp/npm.tgz \
    && echo "${NPM_SHA512}  /tmp/npm.tgz" | sha512sum -c - \
    && rm -rf "${HOME}/.local/lib/node_modules/npm" \
    && mkdir -p "${HOME}/.local/lib/node_modules/npm" \
    && tar -xzf /tmp/npm.tgz --strip-components=1 -C "${HOME}/.local/lib/node_modules/npm" \
    && curl -fsSL --retry 5 --retry-all-errors --connect-timeout 15 \
        "https://registry.npmjs.org/brace-expansion/-/brace-expansion-${NPM_BRACE_EXPANSION_VERSION}.tgz" \
        -o /tmp/npm-brace-expansion.tgz \
    && echo "${NPM_BRACE_EXPANSION_SHA512}  /tmp/npm-brace-expansion.tgz" | sha512sum -c - \
    && rm -rf "${HOME}/.local/lib/node_modules/npm/node_modules/brace-expansion" \
    && mkdir -p "${HOME}/.local/lib/node_modules/npm/node_modules/brace-expansion" \
    && tar -xzf /tmp/npm-brace-expansion.tgz --strip-components=1 -C "${HOME}/.local/lib/node_modules/npm/node_modules/brace-expansion" \
    && npm config set update-notifier false \
    && rm -f /tmp/node.tar.xz /tmp/npm.tgz /tmp/npm-brace-expansion.tgz \
    && rm -rf \
        "${HOME}/.local/include" \
        "${HOME}/.local/CHANGELOG.md" \
        "${HOME}/.local/README.md" \
        "${HOME}/.npm" \
        "${HOME}/.cache"

WORKDIR ${WORKDIR}
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

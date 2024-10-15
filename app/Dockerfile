FROM asolopovas/php-fpm:1.2-php82
ARG APP_USER=www
ARG WORKDIR=/var/www
ARG PNPM_VERSION=${PNPM_VERSION}
ARG HOME=/home/${APP_USER}
ARG NVM_NODEJS_ORG_MIRROR=${NVM_NODEJS_ORG_MIRROR}
ENV APP_USER=${APP_USER}
ENV WORKDIR ${WORKDIR}
ENV HOME ${HOME}
ENV NVM_NODEJS_ORG_MIRROR=${NVM_NODEJS_ORG_MIRROR}
WORKDIR ${WORKDIR}

RUN groupadd -g 1000 ${APP_USER} && useradd -u 1000 -ms /usr/bin/fish -g ${APP_USER} ${APP_USER}
RUN chown -R ${APP_USER}:${APP_USER} ${WORKDIR}

RUN mkdir /etc/sudoers.d; \
    echo "$APP_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$APP_USER; \
    chmod 0440 /etc/sudoers.d/$APP_USER; \
    echo "Set disable_coredump false" > /etc/sudo.conf

RUN apk add --no-cache \
    bash \
    btop \
    coreutils \
    fd \
    fish \
    fzf \
    mysql-client \
    neovim \
    python3 \
    python3-dev \
    py-pip \
    py3-pynvim \
    rsync \
    ripgrep \
    iproute2-ss \
    sudo \
    busybox-extras \
    logrotate \
    libstdc++

RUN echo "fs.inotify.max_user_instances=24288" >> /etc/sysctl.conf
RUN ln -sf /bin/bash /bin/sh

USER ${APP_USER}

ARG FISH=${FISH} OHMYFISH=${OHMYFISH} FZF=${FZF} FDFIND=${FDFIND} NVIM=${NVIM} OHMYBASH=${OHMYBASH} NODE=${NODE} NODE_VERSION=${NODE_VERSION}
RUN FISH=${FISH} OHMYFISH=${OHMYFISH} FZF=${FZF} FDFIND=${FDFIND} NVIM=${NVIM} OHMYBASH=${OHMYBASH} NODE=${NODE} NODE_VERSION=${NODE_VERSION} UNATTENDED=true \
    bash -c "$(curl -fsSLH 'Cache-Control: no-cache' http://raw.githubusercontent.com/asolopovas/dotfiles/master/init.sh)"

# RUN mkdir -p ${HOME}/.local/bin; curl -s http://getcomposer.org/installer | php -- --install-dir=${HOME}/.local/bin --filename=composer
# RUN curl -fsSL https://get.pnpm.io/install.sh | PNPM_VERSION=${PNPM_VERSION} ENV="$HOME/.bashrc" SHELL="$(which bash)" bash -

USER root
COPY config/msmtprc /etc/msmtprc
COPY scripts/* /usr/local/bin/
RUN chmod 4755 /usr/bin/crontab

COPY conf.d/* /usr/local/etc/php/conf.d
RUN touch /var/log/entry.log; chown $APP_USER:$APP_USER /var/log/entry.log; chmod 700 /var/log/entry.log
RUN ln -sf /bin/nvim /usr/local/bin/vim

ARG NEW_RELIC_API_KEY=${NEW_RELIC_API_KEY}
ARG NEW_RELIC_ACCOUNT_ID=${NEW_RELIC_ACCOUNT_ID}
RUN curl -Ls https://download.newrelic.com/install/newrelic-cli/scripts/install.sh | bash \
    && sudo \
    NEW_RELIC_API_KEY=${NEW_RELIC_API_KEY} \
    NEW_RELIC_ACCOUNT_ID=${NEW_RELIC_ACCOUNT_ID} NEW_RELIC_REGION=EU \
    /usr/local/bin/newrelic install -n php-agent-installer

USER $APP_USER

ENTRYPOINT ["entry.sh"]
CMD ["/usr/local/sbin/php-fpm"]

EXPOSE 80 443 9000

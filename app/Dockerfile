FROM asolopovas/php-fpm:3.1
ARG APP_USER=www
ARG WORKDIR=/var/www
ARG HOME=/home/${APP_USER}
ARG NVM_NODEJS_ORG_MIRROR=${NVM_NODEJS_ORG_MIRROR}
ENV HOME ${HOME}
ENV PATH ${WORKDIR}/.local/bin:${HOME}/.composer/vendor/bin:$PATH
ENV WORKDIR ${WORKDIR}
ENV NVM_NODEJS_ORG_MIRROR=${NVM_NODEJS_ORG_MIRROR}
WORKDIR ${WORKDIR}

RUN mkdir ${HOME}; usermod -u 1000 -d ${HOME} -l ${APP_USER} www-data; groupmod -g 1000 -n ${APP_USER} www-data; \
    chown -R 1000:1000 /var/www ${HOME}; rm -rf /home/www-data

# Add User to Sudoers
RUN echo "$APP_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$APP_USER; \
    chmod 0440 /etc/sudoers.d/$APP_USER; \
    echo "Set disable_coredump false" > /etc/sudo.conf;

RUN apk add --no-cache \
    coreutils \
    bash \
    fish \
    sudo \
    fd \
    fzf \
    ripgrep \
    python3 \
    python3-dev \
    py-pip \
    py3-pynvim \
    mysql-client \
    rsync

RUN echo "fs.inotify.max_user_instances=524288" >> /etc/sysctl.conf && sysctl -p

USER ${APP_USER}

ARG FISH=${FISH} OHMYFISH=${OHMYFISH} FZF=${FZF} FDFIND=${FDFIND} NVIM=${NVIM} OHMYBASH=${OHMYBASH} NODE=${NODE} NODE_VERSION=${NODE_VERSION}
RUN FISH=${FISH} OHMYFISH=${OHMYFISH} FZF=${FZF} FDFIND=${FDFIND} NVIM=${NVIM} OHMYBASH=${OHMYBASH} NODE=${NODE} NODE_VERSION=${NODE_VERSION} UNATTENDED=true \
    bash -c "$(curl -fsSLH 'Cache-Control: no-cache' http://raw.githubusercontent.com/asolopovas/dotfiles/master/init.sh)"

RUN mkdir -p ${HOME}/.local/bin; curl -s http://getcomposer.org/installer | php -- --install-dir=${HOME}/.local/bin --filename=composer
COPY --chown=$APP_USER:$APP_USER package.json livereload.js  /var/livereload/

USER root
COPY config/msmtprc /etc/msmtprc
COPY entry.sh /usr/local/bin/
COPY scripts/* /usr/local/bin/
COPY php-fpm.conf /usr/local/etc/
COPY config/conf.d/* /usr/local/etc/php/conf.d
RUN touch /var/log/php-fpm.log; chown $APP_USER:$APP_USER /var/log/php-fpm.log; chmod 700 /var/log/php-fpm.log
RUN touch /var/log/entry.log; chown $APP_USER:$APP_USER /var/log/entry.log; chmod 700 /var/log/entry.log
USER $APP_USER


ENTRYPOINT ["entry.sh"]

EXPOSE 80 443 9000

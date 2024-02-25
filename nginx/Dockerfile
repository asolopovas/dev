FROM nginx:1.25.4-alpine3.18

ARG WORKDIR=/var/www
ARG APP_USER=nginx
ARG GID=1000
ARG UID=1000

RUN apk update && apk upgrade; \
    apk --update add logrotate; \
    apk add --no-cache fish bash shadow openssl certbot certbot-nginx nginx-mod-http-headers-more sudo;

# User setup
RUN [ ! -d $WORKDIR ] && mkdir -p $WORKDIR; \
    groupmod -g ${GID} ${APP_USER} ; \
    usermod -u ${UID} -g ${GID} ${APP_USER}

# Chown Esential Directories
RUN for dir in \
    ${WORKDIR} \
    /run \
    /var/cache/nginx \
    /etc/letsencrypt \
    /etc/letsencrypt/live \
    /var/lib/letsencrypt \
    /var/log/letsencrypt \
    /var/log/nginx \
    /var/www \
    /etc/nginx \
    /etc/nginx/sites-available \
    /etc/nginx/modules-enabled \
    /etc/nginx/sites-enabled \
    /etc/nginx/extras \
    /tmp/nginx/cache; \
    do [ ! -d $dir ] && mkdir -p $dir; chown -R ${UID}:${GID} $dir; done

# Misc setups
RUN mkdir -p /var/cache/nginxfastcgi; \
    chown -R ${UID}:${GID} /var/cache/nginxfastcgi; \
    touch /var/log/messages; \
    echo "0 */12 * * * certbot renew -q --nginx --deploy-hook 'nginx -s reload'" >> /etc/crontabs/root

# various
COPY scripts/* /usr/local/bin
COPY --chown=${UID}:${GID} certs/* /etc/letsencrypt/live
COPY --chown=${UID}:${GID} nginx.conf /etc/nginx
COPY --chown=${UID}:${GID} sites/* /tmp

RUN touch /var/run/nginx.pid && chown ${UID}:${GID} /var/run/nginx.pid;

USER ${APP_USER}
ENTRYPOINT ["entry.sh"]
CMD ["nginx", "-g", "daemon off;"]

EXPOSE 80 443

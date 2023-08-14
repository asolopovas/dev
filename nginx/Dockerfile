FROM nginx:stable-alpine

# Copy nginx config
COPY nginx.conf /etc/nginx/

# Install necessary packages
RUN apk update && apk upgrade; \
    apk --update add logrotate bash; \
    apk add --no-cache shadow openssl certbot certbot-nginx

# Add www-data account
RUN groupmod -g 1000 -n www www-data; \
    adduser -u 1000 -D -S -G www www;

# Create 'messages' file used from 'logrotate'
RUN touch /var/log/messages

# remove the default conf
RUN rm /etc/nginx/conf.d/default.conf

# Copy 'logrotate' config file
COPY logrotate/nginx /etc/logrotate.d/
COPY global /etc/nginx/global
COPY extras /etc/nginx/extras
COPY certs /etc/letsencrypt/live

RUN echo "0 */12 * * * certbot renew -q --nginx --deploy-hook 'nginx -s reload'" >> /etc/crontabs/root

ARG WORKDIR=${WORKDIR}
WORKDIR ${WORKDIR}

CMD ["nginx", "-g", "daemon off;"]
COPY scripts/* /usr/local/bin/
RUN ln -s /bin/bash /bin/zsh
ENTRYPOINT ["entry.sh"]

EXPOSE 80 443

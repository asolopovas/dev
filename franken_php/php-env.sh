#!/bin/bash

set -e

if [ "$EUID" -ne 0 ]; then
    exec sudo -E "$0" "$@"
    exit 1
fi

APP_USER="${APP_USER:-www}"
[ ! -f /var/log/xdebug.log ] && touch /var/log/xdebug.log && chown "$APP_USER:$APP_USER" /var/log/xdebug.log
[ ! -d /var/www/xdebug ] && mkdir /var/www/xdebug && chown -R "$APP_USER:$APP_USER" /var/www/xdebug
[ ! -f /var/www/access.log ] && touch /var/www/access.log && chown "$APP_USER:$APP_USER" /var/www/access.log

if [ "$APP_ENV" = 'local' ]; then
    cp -f "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"
else
    cp -f "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
fi

sed -i "s/XDEBUG_IDEKEY/${XDEBUG_IDEKEY}/g;s/XDEBUG_HOST/${XDEBUG_HOST}/g;s/XDEBUG_MODE/${XDEBUG_MODE}/g;s/XDEBUG_TRIGGER/${XDEBUG_TRIGGER}/g" $PHP_INI_DIR/conf.d/xdebug.ini

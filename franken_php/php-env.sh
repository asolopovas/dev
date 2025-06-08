#!/bin/bash

set -e

if [ "$EUID" -ne 0 ]; then
    exec sudo -E "$0" "$@"
    exit 1
fi

[ ! -f /var/log/xdebug.log ] && touch /var/log/xdebug.log && chown www:www /var/log/xdebug.log
[ ! -d /var/www/xdebug ] && mkdir /var/www/xdebug && chown -R www:www /var/www/xdebug
[ ! -d /var/www/access.log ] && touch /var/www/access.log && chown -R www:www /var/www/access.log

if [ "$APP_ENV" = 'local' ]; then
    cp -f "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"
else
    cp -f "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
fi

sed -i "s/XDEBUG_IDEKEY/${XDEBUG_IDEKEY}/g;s/XDEBUG_HOST/${XDEBUG_HOST}/g;s/XDEBUG_MODE/${XDEBUG_MODE}/g;s/XDEBUG_TRIGGER/${XDEBUG_TRIGGER}/g" $PHP_INI_DIR/conf.d/xdebug.ini
sed -i "s/upload_max_filesize = 2M/upload_max_filesize = 64M/g" $PHP_INI_DIR/php.ini
sed -i "s/post_max_size = 8M/post_max_size = 64M/g" $PHP_INI_DIR/php.ini
sed -i "s/memory_limit = 128M/memory_limit = 1024M/g" $PHP_INI_DIR/php.ini
sed -i "s/max_execution_time = 30/max_execution_time = 60/g" $PHP_INI_DIR/php.ini

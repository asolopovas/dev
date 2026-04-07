#!/bin/bash

set -e

if [ "$EUID" -ne 0 ]; then
    exec sudo -E "$0" "$@"
fi

APP_USER="${APP_USER:-www}"
[ ! -f /var/log/xdebug.log ] && touch /var/log/xdebug.log && chown "$APP_USER:$APP_USER" /var/log/xdebug.log
[ ! -d /var/www/xdebug ] && mkdir -p /var/www/xdebug && chown -R "$APP_USER:$APP_USER" /var/www/xdebug
[ ! -f /var/www/access.log ] && touch /var/www/access.log && chown "$APP_USER:$APP_USER" /var/www/access.log

if [ -x "$HOME/dotfiles/scripts/ops-update-symlinks.sh" ]; then
    "$HOME/dotfiles/scripts/ops-update-symlinks.sh"
fi

CRONTAB_FILE="${CRONTAB_FILE:-}"
if [ -z "$CRONTAB_FILE" ]; then
    for candidate in /var/www/dev/crontab /var/www/*/crontab /var/www/crontab; do
        if [ -f "$candidate" ] && [ -s "$candidate" ]; then
            CRONTAB_FILE="$candidate"
            break
        fi
    done
fi
if [ -f "$CRONTAB_FILE" ] && [ -s "$CRONTAB_FILE" ]; then
    /usr/local/bin/supercronic -passthrough-logs "$CRONTAB_FILE" &
fi

exec docker-php-entrypoint --config /etc/caddy/Caddyfile --adapter caddyfile "$@"

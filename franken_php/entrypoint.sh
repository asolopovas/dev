#!/bin/bash

set -e

/usr/local/bin/php-env.sh

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

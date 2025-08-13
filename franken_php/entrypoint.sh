#!/bin/bash

set -e

/usr/local/bin/php-env.sh

$HOME/dotfiles/scripts/update-symlinks.sh

exec docker-php-entrypoint --config /etc/caddy/Caddyfile --adapter caddyfile "$@"

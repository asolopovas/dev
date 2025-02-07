#!/bin/bash

set -e

/usr/local/bin/php-env.sh

exec docker-php-entrypoint --config /etc/caddy/Caddyfile --adapter caddyfile "$@"

#!/bin/bash

set -e

/usr/local/bin/php-env.sh

$HOME/dotfiles/scripts/ops-update-symlinks.sh

npm install -g @anthropic-ai/claude-code

exec docker-php-entrypoint --config /etc/caddy/Caddyfile --adapter caddyfile "$@"

#!/usr/bin/env bash

NVM_DIR="$HOME/.nvm"

if [ -z "$APP_ENV" ]; then
    echo "APP_ENV is not set" >&2
    exit 1
fi

sudo -E bash -c "source /usr/local/bin/php-env.sh"

if ! crond -l 2 -b; then
    echo "Failed to start cron daemon" >&2
    exit 1
fi

if [ "$LIVERELOAD" = 'true' ]; then
    LR_PATH="/var/livereload"
    source "$NVM_DIR/nvm.sh"
    chown -R www:www $LR_PATH
    yarn --cwd $LR_PATH install
    node $LR_PATH/livereload.js &
fi

if [ ! -f "$HOME/.local/bin/wp" ]; then
    curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar || {
        echo "Download failed"
    }
    chmod +x wp-cli.phar
    mv wp-cli.phar "$HOME/.local/bin/wp" || {
        echo "Move failed"
    }
fi

exec "$@"

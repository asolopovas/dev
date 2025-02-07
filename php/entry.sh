#!/bin/bash

source $HOME/.bashrc

echo "*************************************************"
echo "APP_ENV: $APP_ENV"
echo "APP_DEBUG: $APP_DEBUG"
echo "NVM_DIR: $NVM_DIR"
echo "WORKDIR: $WORKDIR"
echo "GOPATH: $GOPATH"
echo "Dotfiles Dir: $DOTFILES_DIR"
echo "XDEBUG Host: $XDEBUG_HOST"
echo "XDEBUG Mode: $XDEBUG_MODE"
echo "XDEBUG IDE key: $XDEBUG_IDEKEY"
echo "System Path Variables:"
ls-path
echo "*************************************************"

if [ -z "$APP_ENV" ]; then
    echo "APP_ENV is not set" >&2
    exit 1
fi

sudo -E bash -c "source /usr/local/bin/php-env.sh"

if ! crond -d 2; then
    sudo mkdir -p /etc/crontabs/www
    echo "Failed to start cron daemon" >&2
    exit 1
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

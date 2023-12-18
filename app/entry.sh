#!/bin/bash

source $HOME/.bashrc

echo "*************************************************"
echo "APP_ENV: $APP_ENV"
echo "APP_DEBUG: $APP_DEBUG"
echo "LIVERELOAD: $LIVERELOAD"
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

if ! crond -l 2 -b; then
    echo "Failed to start cron daemon" >&2
    exit 1
fi

if [ "$LIVERELOAD" = 'true' ]; then
    # source "$NVM_DIR/nvm.sh"
    PNPM_HOME="$HOME/.local/share/pnpm"
    PATH=$PATH:$PNPM_HOME
    pnpm add -g livereload
    livereload --port 35729 --exts "js,ts,php,twig,html" --exclusions node_modules/,vendor/ "${WORKDIR}"
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

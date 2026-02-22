#!/usr/bin/env bats

COMPOSE_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/docker-compose.yml"
CONTAINER="franken_php"

dc_exec() { docker compose -f "$COMPOSE_FILE" exec -T "$CONTAINER" "$@"; }

@test "PHP extensions are installed" {
    local mods
    mods=$(dc_exec php -m 2>/dev/null)
    [[ "$mods" == *"bcmath"* ]]
    [[ "$mods" == *"calendar"* ]]
    [[ "$mods" == *"exif"* ]]
    [[ "$mods" == *"gd"* ]]
    [[ "$mods" == *"intl"* ]]
    [[ "$mods" == *"mysqli"* ]]
    [[ "$mods" == *"pdo_mysql"* ]]
    [[ "$mods" == *"pdo_pgsql"* ]]
    [[ "$mods" == *"pcntl"* ]]
    [[ "$mods" == *"zip"* ]]
    [[ "$mods" == *"apcu"* ]]
    [[ "$mods" == *"igbinary"* ]]
    [[ "$mods" == *"imagick"* ]]
    [[ "$mods" == *"redis"* ]]
}

@test "shared libraries are resolved for PHP binaries" {
    local missing
    missing=$(dc_exec bash -c 'for f in /usr/local/bin/php /usr/local/bin/frankenphp /usr/local/lib/php/extensions/*/*.so; do ldd "$f" 2>/dev/null | grep "not found" || true; done')
    [[ -z "$missing" ]]
}

@test "CLI tools are available" {
    dc_exec node -v >/dev/null 2>&1
    dc_exec npm -v >/dev/null 2>&1
    dc_exec bun -v >/dev/null 2>&1
    dc_exec bash -c 'XDEBUG_MODE=off composer --version' >/dev/null 2>&1
    dc_exec git --version >/dev/null 2>&1
    dc_exec fish -v >/dev/null 2>&1
    dc_exec wkhtmltopdf --version >/dev/null 2>&1
    dc_exec supercronic --version >/dev/null 2>&1
    dc_exec rg --version >/dev/null 2>&1
    dc_exec fd --version >/dev/null 2>&1
    dc_exec fzf --version >/dev/null 2>&1
}

@test "FrankenPHP serves hosts" {
    local code
    code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 http://phpmyadmin.test 2>/dev/null)
    [[ "$code" == "200" ]]
}

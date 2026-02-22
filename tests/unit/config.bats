#!/usr/bin/env bats

setup()    { load '../test_helper'; common_setup; }
teardown() { common_teardown; }

@test "supervisor_generate_conf creates config with artisan horizon" {
    supervisor_generate_conf "myapp.test" "$SUPERVISOR_DIR/conf.d" >/dev/null 2>&1
    local conf="$SUPERVISOR_DIR/conf.d/myapp_test.conf"
    [[ -f "$conf" ]]
    grep -q "artisan horizon" "$conf"
}

@test "remove_host cleans SSL files" {
    touch "$CERTS_DIR/cleanup.test.key" "$CERTS_DIR/cleanup.test.crt" "$CERTS_DIR/cleanup.test.csr"
    touch "$SUPERVISOR_DIR/conf.d/cleanup_test.conf"
    hosts_json_add "cleanup.test" "wp" "cleanup_wp"

    remove_host "cleanup.test" >/dev/null 2>&1

    [[ ! -e "$CERTS_DIR/cleanup.test.key" ]]
    [[ ! -e "$CERTS_DIR/cleanup.test.crt" ]]
    [[ ! -e "$CERTS_DIR/cleanup.test.csr" ]]
    [[ ! -e "$SUPERVISOR_DIR/conf.d/cleanup_test.conf" ]]
}

@test "remove_host removes JSON entry" {
    hosts_json_add "gone.test" "wp" "gone_wp"
    remove_host "gone.test" >/dev/null 2>&1
    run hosts_json_get_host "gone.test"
    [[ -z "$output" ]]
}

@test "ssl_extfile contains SAN for hostname" {
    run ssl_extfile "myhost.test"
    [[ "$output" == *"DNS.1 = myhost.test"* ]]
    [[ "$output" == *"IP.1 = 127.0.0.1"* ]]
    [[ "$output" == *"subjectAltName"* ]]
}

@test "build_webconf generates Caddy config from template" {
    ssl_generate_host() { :; }
    hosts_json_add "foo.test" "wp" "foo_wp"

    DC="true" build_webconf >/dev/null 2>&1

    local conf="$BACKEND_SITES_DIR/foo.test.conf"
    [[ -f "$conf" ]]
    grep -q "foo.test" "$conf"
    grep -q "/var/www/foo.test" "$conf"
}

@test "build_webconf generates templates.yml with network aliases" {
    ssl_generate_host() { :; }
    hosts_json_add "bar.test" "laravel" "bar_db"

    DC="true" build_webconf >/dev/null 2>&1

    [[ -f "$SCRIPT_DIR/templates.yml" ]]
    grep -q "bar.test" "$SCRIPT_DIR/templates.yml"
    grep -q "aliases" "$SCRIPT_DIR/templates.yml"
}

@test "build_webconf generates crontab for wp hosts" {
    ssl_generate_host() { :; }
    hosts_json_add "wpsite.test" "wp" "wpsite_wp"

    DC="true" build_webconf >/dev/null 2>&1

    [[ -f "$SCRIPT_DIR/crontab" ]]
    grep -q "wp-cron.php" "$SCRIPT_DIR/crontab"
    grep -q "wpsite.test" "$SCRIPT_DIR/crontab"
}

@test "build_webconf skips crontab for laravel hosts" {
    ssl_generate_host() { :; }
    hosts_json_add "larasite.test" "laravel" "larasite_db"

    DC="true" build_webconf >/dev/null 2>&1

    [[ -f "$SCRIPT_DIR/crontab" ]]
    ! grep -q "larasite.test" "$SCRIPT_DIR/crontab"
}

@test "build_webconf sets laravel serve_root to public/" {
    ssl_generate_host() { :; }
    hosts_json_add "lara.test" "laravel" "lara_db"

    DC="true" build_webconf >/dev/null 2>&1

    local conf="$BACKEND_SITES_DIR/lara.test.conf"
    [[ -f "$conf" ]]
    grep -q "/var/www/lara.test/public" "$conf"
}

@test "build_webconf creates .vscode/launch.json with hostname" {
    ssl_generate_host() { :; }
    hosts_json_add "debug.test" "wp" "debug_wp"
    mkdir -p "$WEB_ROOT/debug.test"

    DC="true" build_webconf >/dev/null 2>&1

    local launch="$WEB_ROOT/debug.test/.vscode/launch.json"
    [[ -f "$launch" ]]
    grep -q "debug.test" "$launch"
}

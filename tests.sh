#!/bin/bash

set -o pipefail

PASS=0
FAIL=0
SCRIPT_DIR_ORIG="$(cd "$(dirname "$0")" && pwd)"

setup_env() {
    TEST_TMPDIR=$(mktemp -d)
    export WEB_ROOT="$TEST_TMPDIR/www"
    export SCRIPT_DIR="$TEST_TMPDIR/dev"
    export BACKEND_DIR="$SCRIPT_DIR/franken_php"
    export HOSTS_JSON="$SCRIPT_DIR/web-hosts.json"
    export SUPERVISOR_DIR="$TEST_TMPDIR/supervisor"

    mkdir -p "$WEB_ROOT" "$SCRIPT_DIR" "$BACKEND_DIR/config/sites" "$BACKEND_DIR/config/ssl" "$SUPERVISOR_DIR/conf.d"

    cat > "$HOSTS_JSON" <<-JSON
{
  "output": "$BACKEND_DIR/config/sites",
  "template": "$BACKEND_DIR/config/template.conf",
  "WEB_ROOT": "$WEB_ROOT",
  "hosts": []
}
JSON

    cp "$SCRIPT_DIR_ORIG/launch.json" "$SCRIPT_DIR/launch.json" 2>/dev/null || printf '{}\n' > "$SCRIPT_DIR/launch.json"
    cat > "$BACKEND_DIR/config/template.conf" <<-'CONF'
http://${APP_URL} {
    root * ${SERVE_ROOT}
    php_server
}
CONF

    source "$SCRIPT_DIR_ORIG/web.sh"

    _has_gum() { return 1; }
    select_option() { printf 'off\n'; }
    spin() { "${@:2}"; }
    redirect_remove() { :; }
    db_remove() { :; }
}

teardown_env() {
    [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

assert_eq() {
    [[ "$1" == "$2" ]] && return 0
    printf "    FAIL: %s expected='%s' actual='%s'\n" "${3:-assert_eq}" "$1" "$2"
    return 1
}

assert_contains() {
    [[ "$1" == *"$2"* ]] && return 0
    printf "    FAIL: %s missing='%s'\n" "${3:-assert_contains}" "$2"
    return 1
}

run_test() {
    setup_env
    local name="$1" result=0
    "$name" || result=$?
    teardown_env

    if ((result == 0)); then
        ((++PASS))
        printf "  PASS  %s\n" "$name"
    else
        ((++FAIL))
        printf "  FAIL  %s\n" "$name"
    fi
}

test_make_db_name_cases() {
    assert_eq "example_wp" "$(make_db_name "example.test" "wp")" &&
    assert_eq "example_sub_db" "$(make_db_name "sub.example.test" "laravel")" &&
    assert_eq "example_wp" "$(make_db_name "example.co.uk" "wp")" &&
    assert_eq "db_3oak_wp" "$(make_db_name "3oak.test" "wp")"
}

test_parse_new_host_args() {
    parse_new_host_args -t laravel "mysite.test"
    assert_eq "mysite.test" "$HOST" && assert_eq "laravel" "$TYPE"
}

test_parse_new_host_args_errors() {
    assert_contains "$(parse_new_host_args 2>&1 || true)" "No hostname specified" &&
    assert_contains "$(parse_new_host_args mysite.test -t 2>&1 || true)" "Option -t requires a value"
}

test_main_basics() {
    assert_contains "$(main help)" "Usage: web" &&
    assert_contains "$(main)" "Usage: web" &&
    assert_eq "$SCRIPT_DIR" "$(main dir)"
}

test_main_debug_sets_mode() {
    printf 'XDEBUG_MODE=off\n' > "$SCRIPT_DIR/.env"
    DC="true"
    main debug profile >/dev/null 2>&1
    assert_eq "XDEBUG_MODE=profile" "$(grep '^XDEBUG_MODE=' "$SCRIPT_DIR/.env")"
}

test_hosts_json_core_flow() {
    hosts_json_add "alpha.test" "wp" "alpha_wp"
    assert_eq "alpha_wp" "$(hosts_json_get_db "alpha.test")" || return 1

    hosts_json_add "alpha.test" "wp" "alpha_wp" >/dev/null 2>&1
    assert_eq "1" "$?" || return 1

    hosts_json_remove "alpha.test"
    assert_eq "" "$(hosts_json_get_host "alpha.test")"
}

test_hosts_json_defaults_file() {
    rm -f "$HOSTS_JSON"
    hosts_json_ensure_defaults >/dev/null 2>&1 || true
    [[ -f "$HOSTS_JSON" ]] || return 1
    jq empty "$HOSTS_JSON" >/dev/null 2>&1
}

test_supervisor_conf_minimal() {
    supervisor_generate_conf "myapp.test" "$SUPERVISOR_DIR/conf.d" >/dev/null 2>&1
    local conf="$SUPERVISOR_DIR/conf.d/myapp_test.conf"
    [[ -f "$conf" ]] || return 1
    assert_contains "$(<"$conf")" "artisan horizon"
}

test_remove_host_cleans_local_files() {
    touch "$BACKEND_DIR/config/ssl/cleanup.test.key" "$BACKEND_DIR/config/ssl/cleanup.test.crt" "$BACKEND_DIR/config/ssl/cleanup.test.csr"
    touch "$SUPERVISOR_DIR/conf.d/cleanup_test.conf"
    hosts_json_add "cleanup.test" "wp" "cleanup_wp"
    remove_host "cleanup.test" >/dev/null 2>&1

    [[ ! -e "$BACKEND_DIR/config/ssl/cleanup.test.key" ]] || return 1
    [[ ! -e "$BACKEND_DIR/config/ssl/cleanup.test.crt" ]] || return 1
    [[ ! -e "$BACKEND_DIR/config/ssl/cleanup.test.csr" ]] || return 1
    [[ ! -e "$SUPERVISOR_DIR/conf.d/cleanup_test.conf" ]] || return 1
}

printf "\nweb.sh essential tests\n======================\n\n"

tests=(
    test_make_db_name_cases
    test_parse_new_host_args
    test_parse_new_host_args_errors
    test_main_basics
    test_main_debug_sets_mode
    test_hosts_json_core_flow
    test_hosts_json_defaults_file
    test_supervisor_conf_minimal
    test_remove_host_cleans_local_files
)

for t in "${tests[@]}"; do
    run_test "$t"
done

printf "\nTotal: %d  Passed: %d  Failed: %d\n" "$((PASS + FAIL))" "$PASS" "$FAIL"
((FAIL == 0))

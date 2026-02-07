#!/bin/bash

set -o pipefail

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
SCRIPT_DIR_ORIG="$(cd "$(dirname "$0")" && pwd)"

setup_env() {
    TEST_TMPDIR=$(mktemp -d)
    export WEB_ROOT="$TEST_TMPDIR/www"
    export SCRIPT_DIR="$TEST_TMPDIR/dev"
    export BACKEND_DIR="$SCRIPT_DIR/franken_php"
    export HOSTS_JSON="$SCRIPT_DIR/web-hosts.json"
    mkdir -p "$WEB_ROOT" "$SCRIPT_DIR" "$BACKEND_DIR/config/sites" "$BACKEND_DIR/config/ssl"
    cat > "$HOSTS_JSON" <<-JSON
	{
	    "output": "$BACKEND_DIR/config/sites",
	    "template": "$BACKEND_DIR/config/template.conf",
	    "WEB_ROOT": "$WEB_ROOT",
	    "hosts": []
	}
	JSON
    cp "$SCRIPT_DIR_ORIG/launch.json" "$SCRIPT_DIR/launch.json" 2>/dev/null || echo '{}' > "$SCRIPT_DIR/launch.json"
    cat > "$BACKEND_DIR/config/template.conf" <<-'CONF'
	http://${APP_URL} {
	    root * ${SERVE_ROOT}
	    php_server
	}
	CONF
    source "$SCRIPT_DIR_ORIG/web.sh"
}

teardown_env() { [[ -n "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"; }

assert_eq() {
    [[ "$1" == "$2" ]] && return 0
    echo "    FAIL: ${3:-assertion} expected='$1' actual='$2'"; return 1
}

assert_contains() {
    [[ "$1" == *"$2"* ]] && return 0
    echo "    FAIL: ${3:-assert_contains} missing='$2'"; return 1
}

run_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    setup_env
    local result=0; "$1" || result=$?
    teardown_env
    if [[ $result -eq 0 ]]; then TESTS_PASSED=$((TESTS_PASSED + 1)); echo "  PASS  $1"
    else TESTS_FAILED=$((TESTS_FAILED + 1)); echo "  FAIL  $1"; fi
}

test_hostname_root_simple()       { assert_eq "example" "$(hostname_root "example.test")"; }
test_hostname_root_single()       { assert_eq "localhost" "$(hostname_root "localhost")"; }
test_hostname_root_subdomain()    { assert_eq "example" "$(hostname_root "sub.example.test")"; }
test_hostname_root_deep()         { assert_eq "example" "$(hostname_root "a.b.example.test")"; }
test_hostname_root_known_sld()    { assert_eq "example" "$(hostname_root "example.co.uk")"; }
test_hostname_root_sld_sub()      { assert_eq "example" "$(hostname_root "shop.example.co.uk")"; }

test_make_db_name_wp()            { assert_eq "example_wp" "$(make_db_name "example.test" "wp")"; }
test_make_db_name_wordpress()     { assert_eq "example_wp" "$(make_db_name "example.test" "wordpress")"; }
test_make_db_name_laravel()       { assert_eq "example_db" "$(make_db_name "example.test" "laravel")"; }
test_make_db_name_subdomain()     { assert_eq "example_sub_db" "$(make_db_name "sub.example.test" "laravel")"; }
test_make_db_name_numeric()       { assert_eq "db_3oak_wp" "$(make_db_name "3oak.test" "wp")"; }
test_make_db_name_hyphenated()    { assert_eq "alpha_blend_wp" "$(make_db_name "alpha-blend.test" "wp")"; }
test_make_db_name_deep_sub()      { assert_eq "bloomsart_admin_db" "$(make_db_name "admin.bloomsart.test" "laravel")"; }
test_make_db_name_single()        { assert_eq "localhost_wp" "$(make_db_name "localhost" "wp")"; }
test_make_db_name_unknown_type()  { assert_eq "example_db" "$(make_db_name "example.test" "symfony")"; }

test_hosts_json_add() {
    hosts_json_add "foo.test" "wp" "foo_wp"
    assert_contains "$(hosts_json_get_host "foo.test")" "foo.test"
}

test_hosts_json_add_sets_db() {
    hosts_json_add "bar.test" "wp" "bar_wp"
    assert_eq "bar_wp" "$(hosts_json_get_db "bar.test")"
}

test_hosts_json_add_duplicate_fails() {
    hosts_json_add "dup.test" "wp" "dup_wp"
    hosts_json_add "dup.test" "wp" "dup_wp" 2>/dev/null
    assert_eq "1" "$?"
}

test_hosts_json_add_multiple() {
    hosts_json_add "one.test" "wp" "one_wp"
    hosts_json_add "two.test" "laravel" "two_db"
    assert_eq "2" "$(jq '.hosts | length' "$HOSTS_JSON")"
}

test_hosts_json_get_nonexistent() {
    assert_eq "" "$(hosts_json_get_host "nope.test")"
}

test_hosts_json_remove() {
    hosts_json_add "rm.test" "wp" "rm_wp"
    hosts_json_remove "rm.test"
    assert_eq "" "$(hosts_json_get_host "rm.test")"
}

test_hosts_json_remove_preserves_others() {
    hosts_json_add "keep.test" "wp" "keep_wp"
    hosts_json_add "drop.test" "wp" "drop_wp"
    hosts_json_remove "drop.test"
    assert_eq "1" "$(jq '.hosts | length' "$HOSTS_JSON")" &&
    assert_contains "$(hosts_json_get_host "keep.test")" "keep.test"
}

test_hosts_json_ensure_defaults_existing() {
    hosts_json_ensure_defaults; assert_eq "0" "$?"
}

test_hosts_json_ensure_defaults_creates() {
    rm -f "$HOSTS_JSON"
    hosts_json_ensure_defaults 2>/dev/null || true
    [[ -f "$HOSTS_JSON" ]] || { echo "    FAIL: file not created"; return 1; }
    jq empty "$HOSTS_JSON" 2>/dev/null; assert_eq "0" "$?"
}

test_hosts_json_remove_add_cycle() {
    hosts_json_add "cycle.test" "wp" "cycle_wp" >/dev/null
    hosts_json_remove "cycle.test"
    hosts_json_add "cycle.test" "laravel" "cycle_db" >/dev/null
    assert_eq "cycle_db" "$(hosts_json_get_db "cycle.test")"
}

test_ssl_generate_root() {
    ssl_generate_root "testCA" "testpass" >/dev/null 2>&1
    [[ -f "$CERTS_DIR/testCA.key" ]] || { echo "    FAIL: key missing"; return 1; }
    [[ -f "$CERTS_DIR/testCA.crt" ]] || { echo "    FAIL: cert missing"; return 1; }
    openssl rsa -in "$CERTS_DIR/testCA.key" -passin pass:testpass -check >/dev/null 2>&1
    assert_eq "0" "$?"
}

test_ssl_generate_host() {
    ssl_generate_root "rootCA" "default" >/dev/null 2>&1
    ssl_generate_host "myhost.test" >/dev/null 2>&1
    [[ -f "$CERTS_DIR/myhost.test.key" ]] || { echo "    FAIL: host key missing"; return 1; }
    [[ -f "$CERTS_DIR/myhost.test.crt" ]] || { echo "    FAIL: host cert missing"; return 1; }
    openssl verify -CAfile "$CERTS_DIR/rootCA.crt" "$CERTS_DIR/myhost.test.crt" >/dev/null 2>&1
    assert_eq "0" "$?"
}

test_ssl_generate_host_idempotent() {
    ssl_generate_root "rootCA" "default" >/dev/null 2>&1
    ssl_generate_host "idem.test" >/dev/null 2>&1
    local mtime1; mtime1=$(stat -c %Y "$CERTS_DIR/idem.test.crt")
    sleep 1
    ssl_generate_host "idem.test" >/dev/null 2>&1
    assert_eq "$mtime1" "$(stat -c %Y "$CERTS_DIR/idem.test.crt")"
}

test_ssl_host_has_san() {
    ssl_generate_root "rootCA" "default" >/dev/null 2>&1
    ssl_generate_host "san.test" >/dev/null 2>&1
    local san; san=$(openssl x509 -in "$CERTS_DIR/san.test.crt" -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name")
    assert_contains "$san" "san.test"
}

test_parse_args_defaults() {
    parse_new_host_args "mysite.test"
    assert_eq "mysite.test" "$HOST" && assert_eq "wp" "$TYPE"
}

test_parse_args_explicit_type() {
    parse_new_host_args "mysite.test" -t laravel
    assert_eq "mysite.test" "$HOST" && assert_eq "laravel" "$TYPE"
}

test_parse_args_type_first() {
    parse_new_host_args -t laravel "mysite.test"
    assert_eq "mysite.test" "$HOST" && assert_eq "laravel" "$TYPE"
}

test_parse_args_no_host_fails() {
    assert_contains "$(parse_new_host_args 2>&1 || true)" "No hostname specified"
}

test_supervisor_conf_creates_file() {
    local outdir="$TEST_TMPDIR/supervisor"; mkdir -p "$outdir"
    supervisor_generate_conf "myapp.test" "$outdir" >/dev/null 2>&1
    [[ -f "$outdir/myapp_test.conf" ]] || { echo "    FAIL: conf file not created"; return 1; }
}

test_supervisor_conf_content() {
    local outdir="$TEST_TMPDIR/supervisor"; mkdir -p "$outdir"
    supervisor_generate_conf "myapp.test" "$outdir" >/dev/null 2>&1
    local content; content=$(cat "$outdir/myapp_test.conf")
    assert_contains "$content" "[program:myapp_test]" &&
    assert_contains "$content" "artisan horizon" &&
    assert_contains "$content" "$WEB_ROOT/myapp.test/artisan"
}

test_supervisor_conf_no_host_fails() {
    assert_contains "$(supervisor_generate_conf "" 2>&1 || true)" "No hostname specified"
}

test_main_help()    { assert_contains "$(main help)" "Usage: web"; }
test_main_no_args() { assert_contains "$(main)" "Usage: web"; }
test_main_dir()     { assert_eq "$SCRIPT_DIR" "$(main dir)"; }

test_main_debug_no_mode() {
    assert_contains "$(main debug 2>&1 || true)" "Usage: web debug"
}

test_main_debug_sets_mode() {
    echo "XDEBUG_MODE=off" > "$SCRIPT_DIR/.env"
    DC="echo" main debug profile >/dev/null 2>&1
    assert_eq "XDEBUG_MODE=profile" "$(grep XDEBUG_MODE "$SCRIPT_DIR/.env" | head -1)"
}

echo ""
echo "web.sh tests"
echo "============"
echo ""

while IFS= read -r fn; do run_test "$fn"; done < <(declare -F | awk '$3 ~ /^test_/ {print $3}' | sort)

echo ""
echo "Total: $TESTS_RUN  Passed: $TESTS_PASSED  Failed: $TESTS_FAILED"
[[ $TESTS_FAILED -eq 0 ]]

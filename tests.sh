#!/bin/bash

set -o pipefail

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
CURRENT_TEST=""

TEST_TMPDIR=""
SCRIPT_DIR_ORIG="$(cd "$(dirname "$0")" && pwd)"

setup_env() {
    TEST_TMPDIR=$(mktemp -d)
    export WEB_ROOT="$TEST_TMPDIR/www"
    export SCRIPT_DIR="$TEST_TMPDIR/dev"
    export BACKEND_DIR="$SCRIPT_DIR/franken_php"
    export HOSTS_JSON="$SCRIPT_DIR/web-hosts.json"

    mkdir -p "$WEB_ROOT"
    mkdir -p "$SCRIPT_DIR"
    mkdir -p "$BACKEND_DIR/config/sites"
    mkdir -p "$BACKEND_DIR/config/ssl"

    cat > "$HOSTS_JSON" <<-JSON
	{
	    "output": "$BACKEND_DIR/config/sites",
	    "template": "$BACKEND_DIR/config/template.conf",
	    "WEB_ROOT": "$WEB_ROOT",
	    "hosts": []
	}
	JSON

    cp "$SCRIPT_DIR_ORIG/launch.json" "$SCRIPT_DIR/launch.json" 2>/dev/null || \
        echo '{}' > "$SCRIPT_DIR/launch.json"

    cat > "$BACKEND_DIR/config/template.conf" <<-'CONF'
	http://${APP_URL} {
	    root * ${SERVE_ROOT}
	    php_server
	}
	CONF

    source "$SCRIPT_DIR_ORIG/web.sh"
}

teardown_env() {
    [[ -n "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-}"
    if [[ "$expected" != "$actual" ]]; then
        echo "    FAIL: ${msg:-assertion}"
        echo "      expected: '$expected'"
        echo "      actual:   '$actual'"
        return 1
    fi
    return 0
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-}"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "    FAIL: ${msg:-assert_contains}"
        echo "      expected to contain: '$needle'"
        echo "      in: '$haystack'"
        return 1
    fi
    return 0
}

assert_file_exists() {
    local path="$1"
    local msg="${2:-}"
    if [[ ! -f "$path" ]]; then
        echo "    FAIL: ${msg:-file should exist}: $path"
        return 1
    fi
    return 0
}

assert_file_not_exists() {
    local path="$1"
    local msg="${2:-}"
    if [[ -f "$path" ]]; then
        echo "    FAIL: ${msg:-file should not exist}: $path"
        return 1
    fi
    return 0
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-}"
    if [[ "$expected" != "$actual" ]]; then
        echo "    FAIL: ${msg:-exit code} expected=$expected actual=$actual"
        return 1
    fi
    return 0
}

run_test() {
    local test_name="$1"
    CURRENT_TEST="$test_name"
    TESTS_RUN=$((TESTS_RUN + 1))

    setup_env

    local result=0
    "$test_name" || result=$?

    teardown_env

    if [[ $result -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS  $test_name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL  $test_name"
    fi
}

# =============================================================================
# hostname_root
# =============================================================================

test_hostname_root_simple_domain() {
    assert_eq "example" "$(hostname_root "example.test")"
}

test_hostname_root_single_label() {
    assert_eq "localhost" "$(hostname_root "localhost")"
}

test_hostname_root_subdomain() {
    assert_eq "example" "$(hostname_root "sub.example.test")"
}

test_hostname_root_deep_subdomain() {
    assert_eq "example" "$(hostname_root "a.b.example.test")"
}

test_hostname_root_known_sld_co_uk() {
    assert_eq "example" "$(hostname_root "example.co.uk")"
}

test_hostname_root_known_sld_with_subdomain() {
    assert_eq "example" "$(hostname_root "shop.example.co.uk")"
}

test_hostname_root_com_br() {
    assert_eq "site" "$(hostname_root "site.com.br")"
}

test_hostname_root_two_part() {
    assert_eq "example" "$(hostname_root "example.com")"
}

# =============================================================================
# sanitize_db_identifier
# =============================================================================

test_sanitize_db_identifier_clean() {
    assert_eq "hello_world" "$(sanitize_db_identifier "hello_world")"
}

test_sanitize_db_identifier_special_chars() {
    assert_eq "hello_world_" "$(sanitize_db_identifier "hello-world!")"
}

test_sanitize_db_identifier_leading_underscore() {
    assert_eq "test" "$(sanitize_db_identifier "_test")"
}

test_sanitize_db_identifier_leading_number() {
    assert_eq "db_3oak" "$(sanitize_db_identifier "3oak")"
}

test_sanitize_db_identifier_empty() {
    assert_eq "db" "$(sanitize_db_identifier "")"
}

test_sanitize_db_identifier_dots() {
    assert_eq "a_b_c" "$(sanitize_db_identifier "a.b.c")"
}

test_sanitize_db_identifier_only_special() {
    assert_eq "db" "$(sanitize_db_identifier "---")"
}

# =============================================================================
# make_db_name
# =============================================================================

test_make_db_name_wp_simple() {
    assert_eq "example_wp" "$(make_db_name "example.test" "wp")"
}

test_make_db_name_wordpress_type() {
    assert_eq "example_wp" "$(make_db_name "example.test" "wordpress")"
}

test_make_db_name_laravel() {
    assert_eq "example_db" "$(make_db_name "example.test" "laravel")"
}

test_make_db_name_with_subdomain() {
    assert_eq "example_sub_db" "$(make_db_name "sub.example.test" "laravel")"
}

test_make_db_name_numeric_prefix() {
    assert_eq "db_3oak_wp" "$(make_db_name "3oak.test" "wp")"
}

test_make_db_name_hyphenated() {
    assert_eq "alpha_blend_wp" "$(make_db_name "alpha-blend.test" "wp")"
}

test_make_db_name_deep_subdomain() {
    assert_eq "bloomsart_admin_db" "$(make_db_name "admin.bloomsart.test" "laravel")"
}

test_make_db_name_single_label() {
    assert_eq "localhost_wp" "$(make_db_name "localhost" "wp")"
}

# =============================================================================
# ssl_extfile
# =============================================================================

test_ssl_extfile_contains_hostname() {
    local output
    output=$(ssl_extfile "example.test")
    assert_contains "$output" "DNS.1 = example.test"
}

test_ssl_extfile_contains_ip() {
    local output
    output=$(ssl_extfile "example.test")
    assert_contains "$output" "IP.1 = 127.0.0.1"
}

test_ssl_extfile_contains_key_usage() {
    local output
    output=$(ssl_extfile "example.test")
    assert_contains "$output" "keyUsage=digitalSignature"
}

test_ssl_extfile_no_double_newlines() {
    local output
    output=$(ssl_extfile "example.test")
    if echo "$output" | grep -q '\\n'; then
        echo "    FAIL: ssl_extfile should not contain literal \\n"
        return 1
    fi
    return 0
}

test_ssl_extfile_has_alt_names_section() {
    local output
    output=$(ssl_extfile "my.site")
    assert_contains "$output" "[alt_names]"
}

# =============================================================================
# hosts_json_ensure_defaults
# =============================================================================

test_hosts_json_ensure_defaults_existing_file() {
    hosts_json_ensure_defaults
    local rc=$?
    assert_eq "0" "$rc" "should return 0 when file exists"
}

test_hosts_json_ensure_defaults_creates_file() {
    rm -f "$HOSTS_JSON"
    hosts_json_ensure_defaults 2>/dev/null || true
    assert_file_exists "$HOSTS_JSON" "should create default JSON file"
}

test_hosts_json_ensure_defaults_returns_1_on_creation() {
    rm -f "$HOSTS_JSON"
    hosts_json_ensure_defaults 2>/dev/null
    local rc=$?
    assert_eq "1" "$rc" "should return 1 when file was just created"
}

test_hosts_json_ensure_defaults_valid_json() {
    rm -f "$HOSTS_JSON"
    hosts_json_ensure_defaults 2>/dev/null || true
    jq empty "$HOSTS_JSON" 2>/dev/null
    assert_eq "0" "$?" "created file should be valid JSON"
}

# =============================================================================
# hosts_json_add / hosts_json_get_host / hosts_json_get_db / hosts_json_remove
# =============================================================================

test_hosts_json_add_new_host() {
    hosts_json_add "foo.test" "wp" "foo_wp"
    local result
    result=$(hosts_json_get_host "foo.test")
    assert_contains "$result" "foo.test"
}

test_hosts_json_add_sets_type() {
    hosts_json_add "bar.test" "laravel" "bar_db"
    local host_type
    host_type=$(jq -r --arg hn "bar.test" '.hosts[] | select(.name == $hn) | .type' "$HOSTS_JSON")
    assert_eq "laravel" "$host_type"
}

test_hosts_json_add_sets_db() {
    hosts_json_add "baz.test" "wp" "baz_wp"
    local db
    db=$(hosts_json_get_db "baz.test")
    assert_eq "baz_wp" "$db"
}

test_hosts_json_add_duplicate_fails() {
    hosts_json_add "dup.test" "wp" "dup_wp"
    hosts_json_add "dup.test" "wp" "dup_wp" 2>/dev/null
    local rc=$?
    assert_eq "1" "$rc" "adding duplicate host should fail"
}

test_hosts_json_add_multiple_hosts() {
    hosts_json_add "one.test" "wp" "one_wp"
    hosts_json_add "two.test" "laravel" "two_db"
    local count
    count=$(jq '.hosts | length' "$HOSTS_JSON")
    assert_eq "2" "$count"
}

test_hosts_json_get_host_nonexistent() {
    local result
    result=$(hosts_json_get_host "nonexistent.test")
    assert_eq "" "$result"
}

test_hosts_json_get_db_nonexistent() {
    local result
    result=$(hosts_json_get_db "nonexistent.test")
    assert_eq "" "$result"
}

test_hosts_json_remove_existing() {
    hosts_json_add "remove-me.test" "wp" "remove_me_wp"
    hosts_json_remove "remove-me.test"
    local result
    result=$(hosts_json_get_host "remove-me.test")
    assert_eq "" "$result" "host should be removed"
}

test_hosts_json_remove_nonexistent_is_noop() {
    hosts_json_remove "ghost.test"
    local rc=$?
    assert_eq "0" "$rc" "removing nonexistent host should succeed silently"
}

test_hosts_json_remove_preserves_others() {
    hosts_json_add "keep.test" "wp" "keep_wp"
    hosts_json_add "drop.test" "wp" "drop_wp"
    hosts_json_remove "drop.test"
    local count
    count=$(jq '.hosts | length' "$HOSTS_JSON")
    assert_eq "1" "$count"
    local remaining
    remaining=$(hosts_json_get_host "keep.test")
    assert_contains "$remaining" "keep.test"
}

# =============================================================================
# parse_new_host_args
# =============================================================================

test_parse_args_defaults_to_wp() {
    parse_new_host_args "mysite.test"
    assert_eq "mysite.test" "$HOST" &&
    assert_eq "wp" "$TYPE"
}

test_parse_args_explicit_type() {
    parse_new_host_args "mysite.test" -t laravel
    assert_eq "mysite.test" "$HOST" &&
    assert_eq "laravel" "$TYPE"
}

test_parse_args_type_before_host() {
    parse_new_host_args -t laravel "mysite.test"
    assert_eq "mysite.test" "$HOST" &&
    assert_eq "laravel" "$TYPE"
}

test_parse_args_wp_type() {
    parse_new_host_args "site.test" -t wp
    assert_eq "wp" "$TYPE"
}

test_parse_args_no_host_fails() {
    local output
    output=$(parse_new_host_args 2>&1) || true
    assert_contains "$output" "No hostname specified"
}

# =============================================================================
# SSL generation
# =============================================================================

test_ssl_generate_root_creates_key_and_cert() {
    ssl_generate_root "testCA" "testpass" >/dev/null 2>&1
    assert_file_exists "$CERTS_DIR/testCA.key" "root key should exist" &&
    assert_file_exists "$CERTS_DIR/testCA.crt" "root cert should exist"
}

test_ssl_generate_root_key_is_valid() {
    ssl_generate_root "testCA" "testpass" >/dev/null 2>&1
    openssl rsa -in "$CERTS_DIR/testCA.key" -passin pass:testpass -check >/dev/null 2>&1
    assert_eq "0" "$?" "root key should be a valid RSA key"
}

test_ssl_generate_root_cert_is_valid() {
    ssl_generate_root "testCA" "testpass" >/dev/null 2>&1
    openssl x509 -in "$CERTS_DIR/testCA.crt" -noout >/dev/null 2>&1
    assert_eq "0" "$?" "root cert should be a valid X.509 certificate"
}

test_ssl_generate_host_creates_key_and_cert() {
    ssl_generate_root "rootCA" "default" >/dev/null 2>&1
    ssl_generate_host "myhost.test" >/dev/null 2>&1
    assert_file_exists "$CERTS_DIR/myhost.test.key" "host key should exist" &&
    assert_file_exists "$CERTS_DIR/myhost.test.crt" "host cert should exist"
}

test_ssl_generate_host_cert_has_san() {
    ssl_generate_root "rootCA" "default" >/dev/null 2>&1
    ssl_generate_host "myhost.test" >/dev/null 2>&1
    local san
    san=$(openssl x509 -in "$CERTS_DIR/myhost.test.crt" -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name")
    assert_contains "$san" "myhost.test" "cert should contain SAN for the host"
}

test_ssl_generate_host_is_idempotent() {
    ssl_generate_root "rootCA" "default" >/dev/null 2>&1
    ssl_generate_host "idem.test" >/dev/null 2>&1
    local mtime1
    mtime1=$(stat -c %Y "$CERTS_DIR/idem.test.crt")
    sleep 1
    ssl_generate_host "idem.test" >/dev/null 2>&1
    local mtime2
    mtime2=$(stat -c %Y "$CERTS_DIR/idem.test.crt")
    assert_eq "$mtime1" "$mtime2" "re-running should not regenerate existing cert"
}

test_ssl_generate_host_cert_signed_by_root() {
    ssl_generate_root "rootCA" "default" >/dev/null 2>&1
    ssl_generate_host "signed.test" >/dev/null 2>&1
    openssl verify -CAfile "$CERTS_DIR/rootCA.crt" "$CERTS_DIR/signed.test.crt" >/dev/null 2>&1
    assert_eq "0" "$?" "host cert should verify against root CA"
}

# =============================================================================
# supervisor_generate_conf
# =============================================================================

test_supervisor_conf_creates_file() {
    local outdir="$TEST_TMPDIR/supervisor"
    mkdir -p "$outdir"
    supervisor_generate_conf "myapp.test" "$outdir" >/dev/null 2>&1
    assert_file_exists "$outdir/myapp_test.conf"
}

test_supervisor_conf_contains_program_name() {
    local outdir="$TEST_TMPDIR/supervisor"
    mkdir -p "$outdir"
    supervisor_generate_conf "myapp.test" "$outdir" >/dev/null 2>&1
    local content
    content=$(cat "$outdir/myapp_test.conf")
    assert_contains "$content" "[program:myapp_test]"
}

test_supervisor_conf_contains_horizon_command() {
    local outdir="$TEST_TMPDIR/supervisor"
    mkdir -p "$outdir"
    supervisor_generate_conf "myapp.test" "$outdir" >/dev/null 2>&1
    local content
    content=$(cat "$outdir/myapp_test.conf")
    assert_contains "$content" "artisan horizon"
}

test_supervisor_conf_contains_correct_path() {
    local outdir="$TEST_TMPDIR/supervisor"
    mkdir -p "$outdir"
    supervisor_generate_conf "myapp.test" "$outdir" >/dev/null 2>&1
    local content
    content=$(cat "$outdir/myapp_test.conf")
    assert_contains "$content" "$WEB_ROOT/myapp.test/artisan"
}

test_supervisor_conf_no_host_fails() {
    local output
    output=$(supervisor_generate_conf "" 2>&1) || true
    assert_contains "$output" "No hostname specified"
}

# =============================================================================
# require_cmd
# =============================================================================

test_require_cmd_existing_command() {
    require_cmd bash
    assert_eq "0" "$?" "bash should be found"
}

test_require_cmd_nonexistent_fails() {
    local output
    output=$(require_cmd "nonexistent_command_xyz_12345" 2>&1) || true
    assert_contains "$output" "not installed"
}

# =============================================================================
# require_host
# =============================================================================

test_require_host_with_value() {
    require_host "example.test" "test-cmd"
    assert_eq "0" "$?"
}

test_require_host_empty_fails() {
    local output
    output=$(require_host "" "test-cmd" 2>&1) || true
    assert_contains "$output" "No hostname specified"
}

test_require_host_unset_fails() {
    local output
    output=$(require_host 2>&1) || true
    assert_contains "$output" "No hostname specified"
}

# =============================================================================
# show_help
# =============================================================================

test_show_help_contains_usage() {
    local output
    output=$(show_help)
    assert_contains "$output" "Usage: web <command>"
}

test_show_help_lists_new_host() {
    local output
    output=$(show_help)
    assert_contains "$output" "new-host"
}

test_show_help_lists_build() {
    local output
    output=$(show_help)
    assert_contains "$output" "build"
}

test_show_help_lists_debug() {
    local output
    output=$(show_help)
    assert_contains "$output" "debug"
}

# =============================================================================
# main dispatch
# =============================================================================

test_main_help_shows_usage() {
    local output
    output=$(main help)
    assert_contains "$output" "Usage: web <command>"
}

test_main_no_args_shows_help() {
    local output
    output=$(main)
    assert_contains "$output" "Usage: web <command>"
}

test_main_dash_h_shows_help() {
    local output
    output=$(main -h)
    assert_contains "$output" "Usage: web <command>"
}

test_main_dash_dash_help_shows_help() {
    local output
    output=$(main --help)
    assert_contains "$output" "Usage: web <command>"
}

test_main_unknown_command_shows_help() {
    local output
    output=$(main "nonexistent-command-xyz")
    assert_contains "$output" "Usage: web <command>"
}

test_main_dir_outputs_script_dir() {
    local output
    output=$(main dir)
    assert_eq "$SCRIPT_DIR" "$output"
}

test_main_debug_no_mode_fails() {
    local output
    output=$(main debug 2>&1) || true
    assert_contains "$output" "Usage: web debug"
}

test_main_debug_sets_env_var() {
    echo "XDEBUG_MODE=off" > "$SCRIPT_DIR/.env"

    DC="echo" main debug profile >/dev/null 2>&1

    local mode
    mode=$(grep XDEBUG_MODE "$SCRIPT_DIR/.env" | head -1)
    assert_eq "XDEBUG_MODE=profile" "$mode"
}

test_main_hostssl_no_host_fails() {
    local output
    output=$(main hostssl 2>&1) || true
    assert_contains "$output" "No hostname specified"
}

test_main_git_update_no_theme_fails() {
    local output
    output=$(main git-update user 2>&1) || true
    assert_contains "$output" "Usage: web git-update"
}

# =============================================================================
# dc_build
# =============================================================================

test_dc_build_all_services() {
    local output
    DC="echo" output=$(dc_build 2>&1)
    assert_contains "$output" "Building all services"
}

test_dc_build_specific_service() {
    local output
    DC="echo" output=$(dc_build "franken_php" 2>&1)
    assert_contains "$output" "Building service: franken_php"
}

test_dc_build_no_cache_flag() {
    local output
    DC="echo" output=$(dc_build "franken_php" "--no-cache" 2>&1)
    assert_contains "$output" "--no-cache" &&
    assert_contains "$output" "franken_php"
}

test_dc_build_invalid_cache_flag_ignored() {
    local output
    DC="echo" output=$(dc_build "myservice" "--invalid" 2>&1)
    if echo "$output" | grep -q -- "--invalid"; then
        echo "    FAIL: invalid flag should be ignored"
        return 1
    fi
    return 0
}

# =============================================================================
# is_wsl
# =============================================================================

test_is_wsl_on_linux() {
    if grep -q WSL /proc/version 2>/dev/null; then
        is_wsl
        assert_eq "0" "$?" "should detect WSL"
    else
        is_wsl
        assert_eq "1" "$?" "should not detect WSL on native Linux"
    fi
}

# =============================================================================
# log / warn / info / die
# =============================================================================

test_log_outputs_message() {
    local output
    output=$(log "hello world")
    assert_eq "hello world" "$output"
}

test_warn_outputs_to_stderr() {
    local output
    output=$(warn "warning msg" 2>&1 >/dev/null)
    assert_contains "$output" "warning msg"
}

test_info_outputs_message() {
    local output
    output=$(info "info msg")
    assert_contains "$output" "info msg"
}

test_die_outputs_error_and_exits() {
    local output rc
    output=$(die "fatal error" 2>&1) || rc=$?
    assert_contains "$output" "fatal error" &&
    assert_eq "1" "$rc"
}

# =============================================================================
# install command
# =============================================================================

test_main_install_creates_symlinks() {
    mkdir -p "$HOME/.local/bin"
    mkdir -p "$HOME/.config/fish/completions"

    cp "$SCRIPT_DIR_ORIG/web.sh" "$SCRIPT_DIR/web.sh"
    touch "$SCRIPT_DIR/web.completions.fish"

    main install >/dev/null 2>&1

    [[ -L "$HOME/.local/bin/web" ]] || {
        echo "    FAIL: web symlink not created"
        return 1
    }
    return 0
}

# =============================================================================
# hosts_json_query
# =============================================================================

test_hosts_json_query_reads_hosts() {
    hosts_json_add "query.test" "wp" "query_wp" >/dev/null
    local count
    count=$(hosts_json_query '.hosts | length')
    assert_eq "1" "$count"
}

test_hosts_json_query_filter() {
    hosts_json_add "a.test" "wp" "a_wp" >/dev/null
    hosts_json_add "b.test" "laravel" "b_db" >/dev/null
    local name
    name=$(hosts_json_query -r '.hosts[] | select(.type == "laravel") | .name')
    assert_eq "b.test" "$name"
}

# =============================================================================
# Integration: make_db_name matches real web-hosts.json patterns
# =============================================================================

test_make_db_name_matches_3oak() {
    assert_eq "db_3oak_wp" "$(make_db_name "3oak.test" "wp")"
}

test_make_db_name_matches_alpha_blend() {
    assert_eq "alpha_blend_wp" "$(make_db_name "alpha-blend.test" "wp")"
}

test_make_db_name_matches_db_woodlandflooring() {
    assert_eq "woodlandflooring_db_db" "$(make_db_name "db.woodlandflooring.test" "laravel")"
}

test_make_db_name_matches_admin_bloomsart() {
    assert_eq "bloomsart_admin_db" "$(make_db_name "admin.bloomsart.test" "laravel")"
}

test_make_db_name_matches_laravel() {
    assert_eq "laravel_db" "$(make_db_name "laravel.test" "laravel")"
}

# =============================================================================
# Edge cases
# =============================================================================

test_hostname_root_empty_string() {
    local result
    result=$(hostname_root "")
    assert_eq "" "$result"
}

test_make_db_name_unknown_type_uses_db_suffix() {
    assert_eq "example_db" "$(make_db_name "example.test" "symfony")"
}

test_hosts_json_add_then_get_db() {
    hosts_json_add "cycle.test" "wp" "cycle_wp" >/dev/null
    local db
    db=$(hosts_json_get_db "cycle.test")
    assert_eq "cycle_wp" "$db"
}

test_hosts_json_remove_then_add_again() {
    hosts_json_add "reuse.test" "wp" "reuse_wp" >/dev/null
    hosts_json_remove "reuse.test"
    hosts_json_add "reuse.test" "laravel" "reuse_db" >/dev/null
    local db
    db=$(hosts_json_get_db "reuse.test")
    assert_eq "reuse_db" "$db"
}

# =============================================================================
# Runner
# =============================================================================

echo ""
echo "web.sh test suite"
echo "================="
echo ""

while IFS= read -r fn; do
    run_test "$fn"
done < <(declare -F | awk '$3 ~ /^test_/ {print $3}' | sort)

echo ""
echo "-----------------------------"
echo "Total: $TESTS_RUN  Passed: $TESTS_PASSED  Failed: $TESTS_FAILED"
echo "-----------------------------"

[[ $TESTS_FAILED -eq 0 ]]

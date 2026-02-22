PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME:-$0}")/../.." && pwd)"

common_setup() {
    TEST_TMPDIR=$(mktemp -d)
    export WEB_ROOT="$TEST_TMPDIR/www"
    export SCRIPT_DIR="$TEST_TMPDIR/dev"
    export BACKEND_DIR="$SCRIPT_DIR/franken_php"
    export BACKEND_CONFIG_DIR="$BACKEND_DIR/config"
    export BACKEND_SITES_DIR="$BACKEND_CONFIG_DIR/sites"
    export HOSTS_JSON="$SCRIPT_DIR/web-hosts.json"
    export SUPERVISOR_DIR="$TEST_TMPDIR/supervisor"
    export CERTS_DIR="$BACKEND_CONFIG_DIR/ssl"

    mkdir -p "$WEB_ROOT" "$SCRIPT_DIR" "$BACKEND_SITES_DIR" "$CERTS_DIR" "$SUPERVISOR_DIR/conf.d"

    cat > "$HOSTS_JSON" <<-JSON
{
  "output": "$BACKEND_SITES_DIR",
  "template": "$BACKEND_CONFIG_DIR/template.conf",
  "WEB_ROOT": "$WEB_ROOT",
  "hosts": []
}
JSON

    cp "$PROJECT_ROOT/launch.json" "$SCRIPT_DIR/launch.json" 2>/dev/null || printf '{}\n' > "$SCRIPT_DIR/launch.json"

    cat > "$BACKEND_CONFIG_DIR/template.conf" <<-'CONF'
http://${APP_URL} {
    root * ${SERVE_ROOT}
    php_server
}
CONF

    local _old_errexit=""
    [[ -o errexit ]] && _old_errexit=1
    set +o errexit
    source "$PROJECT_ROOT/web.sh"
    [[ -n "$_old_errexit" ]] && set -o errexit

    _has_gum() { return 1; }
    select_option() { printf 'off\n'; }
    spin() { "${@:2}"; }
    redirect_remove() { :; }
    redirect_add() { :; }
    db_remove() { :; }
    db_exists() { return 1; }
    db_create() { :; }
}

common_teardown() {
    [[ -n "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

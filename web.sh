#!/bin/bash

set -o errexit
set -o pipefail

WEB_ROOT="${WEB_ROOT:-$HOME/www}"
USERNAME="${USERNAME:-$(whoami)}"
SCRIPT_DIR="${SCRIPT_DIR:-$HOME/www/dev}"
BACKEND_DIR="${BACKEND_DIR:-$SCRIPT_DIR/franken_php}"
BACKEND_CONFIG_DIR="$BACKEND_DIR/config"
BACKEND_SITES_DIR="$BACKEND_CONFIG_DIR/sites"
HOSTS_JSON="${HOSTS_JSON:-$SCRIPT_DIR/web-hosts.json}"
CERTS_DIR="$BACKEND_CONFIG_DIR/ssl"
ROOT_KEY="$CERTS_DIR/rootCA.key"
ROOT_CRT="$CERTS_DIR/rootCA.crt"
DC="docker compose -f $SCRIPT_DIR/docker-compose.yml"
KNOWN_SLDS="co.uk gov.uk com.br co.jp"
_HOSTS_MODULE_PATH_CACHED=""

die()  { printf '\033[31mError: %s\033[0m\n' "$1" >&2; exit 1; }
warn() { printf '\033[0;33m%s\033[0m\n' "$1" >&2; }
info() { printf '\033[0;32m%s\033[0m\n' "$1"; }
log()  { printf '%s\n' "$1"; }

require_cmd()    { command -v "$1" &>/dev/null || die "$1 is not installed."; }
require_host()   { [[ -n "${1:-}" ]] || die "No hostname specified. Usage: web $2 <hostname>"; }
require_docker() { require_cmd docker; docker info &>/dev/null || die "Docker daemon is not running."; }

ensure_jq() { command -v jq &>/dev/null || { log "Installing jq..."; sudo apt update && sudo apt install -y jq; }; }

confirm() {
    local reply
    while true; do
        read -rp "$1 [y/n] " -n 1 reply; echo
        case "$reply" in
            [Yy]) return 0 ;; [Nn]) return 1 ;; *) warn "Please enter y or n." ;;
        esac
    done
}

is_wsl() { grep -q WSL /proc/version 2>/dev/null; }

powershell_exe() {
    command -v pwsh.exe >/dev/null 2>&1 && echo "pwsh.exe" || echo "powershell.exe"
}

hosts_json_query()    { jq "$@" "$HOSTS_JSON"; }
hosts_json_get_host() { hosts_json_query -r --arg hn "$1" '.hosts[] | select(.name == $hn)'; }
hosts_json_get_db()   { hosts_json_query -r --arg hn "$1" '.hosts[] | select(.name == $hn) | .db'; }

hosts_json_add() {
    local host_name="$1" host_type="$2" db_name="$3"
    [[ -n "$(hosts_json_get_host "$host_name")" ]] && { warn "Host $host_name already exists."; return 1; }
    local new_host tmp
    new_host=$(jq -n --arg hn "$host_name" --arg ht "$host_type" --arg db "$db_name" '{name: $hn, type: $ht, db: $db}')
    tmp=$(mktemp)
    jq ".hosts += [$new_host]" "$HOSTS_JSON" > "$tmp" && mv "$tmp" "$HOSTS_JSON"
}

hosts_json_remove() {
    local host_name="$1"
    [[ -z "$(hosts_json_get_host "$host_name")" ]] && return 0
    local tmp; tmp=$(mktemp)
    jq --arg hn "$host_name" 'del(.hosts[] | select(.name == $hn))' "$HOSTS_JSON" > "$tmp" && mv "$tmp" "$HOSTS_JSON"
}

hosts_json_ensure_defaults() {
    [[ -f "$HOSTS_JSON" ]] && return 0
    log "No config file found, creating default one"
    cat > "$HOSTS_JSON" <<-ENDJSON
	{
	    "output": "$BACKEND_SITES_DIR",
	    "template": "$BACKEND_CONFIG_DIR/template.conf",
	    "WEB_ROOT": "$WEB_ROOT",
	    "hosts": []
	}
	ENDJSON
    return 1
}

hostname_root() {
    local domain="$1"
    local -a parts; IFS='.' read -r -a parts <<< "$domain"
    local n=${#parts[@]}
    ((n <= 1)) && { echo "$domain"; return; }
    local tld_count=1 last_two="${parts[n-2]}.${parts[n-1]}" sld
    for sld in $KNOWN_SLDS; do [[ "$last_two" == "$sld" ]] && { tld_count=2; break; }; done
    local main_idx=$((n - tld_count - 1))
    ((main_idx < 0)) && main_idx=0
    echo "${parts[main_idx]}"
}

sanitize_db_identifier() {
    local cleaned
    cleaned=$(printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9_' '_')
    while [[ "$cleaned" == _* ]]; do cleaned="${cleaned#_}"; done
    [[ -z "$cleaned" ]] && cleaned="db"
    [[ "$cleaned" =~ ^[0-9] ]] && cleaned="db_${cleaned}"
    printf '%s\n' "$cleaned"
}

make_db_name() {
    local host="$1" host_type="$2"
    local -a parts; IFS='.' read -r -a parts <<< "$host"
    local n=${#parts[@]} main_domain sub_domain tld_count=1

    if ((n <= 1)); then
        main_domain="$host"; sub_domain=""
    else
        ((n >= 2)) && ((${#parts[n-2]} <= 3)) && tld_count=2
        local main_idx=$((n - 1 - tld_count))
        ((main_idx < 0)) && main_idx=0
        main_domain="${parts[main_idx]}"; sub_domain=""
        if ((main_idx > 0)); then
            sub_domain="${parts[0]}"
            for ((i = 1; i < main_idx; i++)); do sub_domain="${sub_domain}.${parts[i]}"; done
        fi
    fi

    local db_name
    [[ -z "$sub_domain" || "$sub_domain" == "$main_domain" ]] && db_name="$main_domain" || db_name="${main_domain}_$(echo "$sub_domain" | tr '.' '_')"
    case "$host_type" in
        wordpress|wp) db_name="${db_name}_wp" ;; *) db_name="${db_name}_db" ;;
    esac
    sanitize_db_identifier "$(echo "$db_name" | tr '.' '_')"
}

db_create() {
    local db_name; db_name=$(hosts_json_get_db "$1")
    [[ -z "$db_name" ]] && die "No database configured for host $1"
    log "Creating database and user: $db_name"
    $DC exec mariadb mariadb -uroot -psecret -e "CREATE USER IF NOT EXISTS '${db_name}'@'%' IDENTIFIED BY 'secret';"
    $DC exec mariadb mariadb -uroot -psecret -e "CREATE DATABASE IF NOT EXISTS \`${db_name}\`;"
    $DC exec mariadb mariadb -uroot -psecret -e "GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_name}'@'%';"
}

db_remove() {
    local db_name; db_name=$(hosts_json_get_db "$1")
    [[ -z "$db_name" ]] && return 0
    log "Removing database and user: $db_name"
    $DC exec mariadb mariadb -uroot -psecret -e "DROP DATABASE IF EXISTS \`${db_name}\`;"
    $DC exec mariadb mariadb -uroot -psecret -e "DROP USER IF EXISTS '${db_name}'@'%';"
}

db_exists() {
    local result
    result=$(docker exec dev-mariadb-1 mariadb -u root -psecret -Nse \
        "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='$1'")
    [[ -n "$result" ]]
}

ssl_extfile() {
    cat <<-EOF
	authorityKeyIdentifier=keyid,issuer
	basicConstraints=CA:FALSE
	keyUsage=digitalSignature,nonRepudiation,keyEncipherment,dataEncipherment
	subjectAltName = @alt_names
	[alt_names]
	DNS.1 = $1
	IP.1 = 127.0.0.1
	EOF
}

ssl_generate_root() {
    local filename="${1:-rootCA}" passphrase="${2:-default}" validity_days=29200
    local subject="/C=GB/ST=London/L=London/O=Lyntouch/OU=IT Department/CN=Lyntouch Self-Signed RootCA/emailAddress=info@lyntouch.com"
    local expiry_date; expiry_date=$(date -d "+${validity_days} days" "+%Y-%m-%d") || die "Failed to calculate expiry date."
    mkdir -p "$CERTS_DIR"
    local key_path="$CERTS_DIR/${filename}.key" crt_path="$CERTS_DIR/${filename}.crt"
    log "Creating Root CA: $key_path (expires $expiry_date)"
    openssl genrsa -des3 -passout "pass:$passphrase" -out "$key_path" 4096 || return 1
    openssl req -x509 -new -nodes -passin "pass:$passphrase" -key "$key_path" -sha256 -days "$validity_days" -subj "$subject" -out "$crt_path" || return 1
    info "Root CA created successfully"
}

ssl_generate_host() {
    local ssl_host="$1"
    local crt_path="$CERTS_DIR/${ssl_host}.crt" key_path="$CERTS_DIR/${ssl_host}.key" csr_path="$CERTS_DIR/${ssl_host}.csr"
    local subject="/C=GB/ST=London/L=London/O=${ssl_host}/OU=IT Department/CN=Lyntouch Self-Signed Host Certificate/emailAddress=info@lyntouch.com"
    if [[ ! -f "$key_path" ]]; then
        info "Generating SSL key for $ssl_host"
        openssl req -new -sha256 -nodes -out "$csr_path" -newkey rsa:2048 -subj "$subject" -keyout "$key_path"
    fi
    if [[ ! -f "$crt_path" ]]; then
        info "Generating SSL certificate for $ssl_host"
        openssl x509 -req -passin pass:default -in "$csr_path" -CA "$ROOT_CRT" -CAkey "$ROOT_KEY" \
            -CAcreateserial -out "$crt_path" -days 500 -sha256 -extfile <(ssl_extfile "$ssl_host")
    fi
}

ssl_import_root_to_chrome() {
    is_wsl && die "Chrome root CA import is not supported on WSL."
    local cert_file="${1:-$ROOT_CRT}" cert_nickname="${2:-Root CA}"
    [[ -f "$cert_file" ]] || die "Certificate file not found: $cert_file"
    openssl x509 -outform der -in "$cert_file" -out "${cert_file}.der"
    local cert_dir="$HOME/.pki/nssdb"
    [[ -d "$cert_dir" ]] || { mkdir -p "$cert_dir"; certutil -N -d "$cert_dir"; }
    certutil -d "sql:$cert_dir" -A -t "C,," -n "$cert_nickname" -i "${cert_file}.der"
    info "Certificate imported to Chrome with nickname: $cert_nickname"
}

_resolve_hosts_module_path() {
    [[ -n "$_HOSTS_MODULE_PATH_CACHED" ]] && { echo "$_HOSTS_MODULE_PATH_CACHED"; return 0; }
    local search_paths=(
        "/mnt/c/Users/*/Documents/PowerShell/Modules/Hosts/*/Hosts.psd1"
        "/mnt/c/Users/*/Documents/WindowsPowerShell/Modules/Hosts/*/Hosts.psd1"
        "/mnt/c/Users/*/Documents/PowerShell/Modules/Hosts/*/Hosts.psm1"
        "/mnt/c/Users/*/Documents/WindowsPowerShell/Modules/Hosts/*/Hosts.psm1"
    )
    shopt -s nullglob
    for candidate in "${search_paths[@]}"; do
        for match in $candidate; do _HOSTS_MODULE_PATH_CACHED="$match"; break 2; done
    done
    shopt -u nullglob
    echo "$_HOSTS_MODULE_PATH_CACHED"
}

_run_host_mapping_cmdlet() {
    local cmdlet="$1" hostname="$2"
    local module_path import_cmd
    module_path=$(_resolve_hosts_module_path)
    [[ -n "$module_path" ]] \
        && import_cmd="Import-Module '$(wslpath -w "$module_path")' -ErrorAction Stop" \
        || import_cmd="Import-Module Hosts -ErrorAction Stop"
    "$(powershell_exe)" -NoProfile -Command "& {
        $import_cmd
        \$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (\$isAdmin) { ${cmdlet} '${hostname}' }
        else { Start-Process -FilePath (Get-Process -Id \$PID).Path -Verb RunAs -Wait -ArgumentList '-NoProfile', '-Command', \"$import_cmd; ${cmdlet} '${hostname}'\" }
    }"
}

redirect_add() {
    local host="$1"
    if is_wsl; then
        grep -qP "^\s*127\.0\.0\.1.*${host}(?:\s+|$)" "/mnt/c/Windows/System32/drivers/etc/hosts" 2>/dev/null && return 0
        log "Adding host redirection for \"$host\""
        _run_host_mapping_cmdlet "New-HostnameMapping" "$host" || { warn "Failed to add host mapping for $host."; return 1; }
    else
        getent hosts "$host" &>/dev/null && return 0
        log "Adding host redirection for \"$host\""
        echo "127.0.0.1 $host" | sudo tee -a /etc/hosts >/dev/null
    fi
}

redirect_remove() {
    local host="$1"
    log "Removing host redirection for \"$host\""
    if is_wsl; then
        _run_host_mapping_cmdlet "Remove-HostnameMapping" "$host" || { warn "Failed to remove host mapping for $host."; return 1; }
    else
        grep -q "$host" /etc/hosts 2>/dev/null && sudo sed -i.bak "/$host/d" /etc/hosts
    fi
}

build_webconf() {
    hosts_json_ensure_defaults || return 1
    find "$BACKEND_SITES_DIR" -type f ! -name 'phpmyadmin.test.conf' ! -name '.gitkeep' -delete
    if ! jq -e '.hosts[] | select(.name == "phpmyadmin.test")' "$HOSTS_JSON" >/dev/null 2>&1; then
        redirect_add "phpmyadmin.test"
        ssl_generate_host "phpmyadmin.test"
    fi

    { echo "services:"; echo "  franken_php:"; echo "    networks:"; echo "      dev_network:"; echo "        aliases:"
      hosts_json_query -r '.hosts[].name' | while read -r name; do echo "          - $name"; done
    } > "$SCRIPT_DIR/templates.yml"

    : > "$SCRIPT_DIR/crontab"
    local row host_name host_type db serve_root site_conf debugout
    mapfile -t host_entries < <(hosts_json_query -c '.hosts[]')

    for row in "${host_entries[@]}"; do
        host_name=$(jq -r '.name' <<< "$row"); host_type=$(jq -r '.type' <<< "$row"); db=$(jq -r '.db' <<< "$row")
        log "Processing host: $host_name"
        serve_root="/var/www/$host_name"; site_conf="$BACKEND_SITES_DIR/${host_name}.conf"; debugout="$WEB_ROOT/$host_name/.vscode"

        [[ "$host_type" == "wp" || "$host_type" == "wordpress" ]] && \
            echo "* * * * * cd $serve_root && php $serve_root/wp-cron.php >/proc/self/fd/1 2>/proc/self/fd/2" >> "$SCRIPT_DIR/crontab"

        redirect_add "$host_name"
        ssl_generate_host "$host_name"
        [[ "$host_type" == "laravel" ]] && serve_root="$serve_root/public"

        mkdir -p "$debugout"
        sed -e "s|\${HOSTNAME}|$host_name|g" "$SCRIPT_DIR/launch.json" > "$debugout/launch.json"
        sed -e "s|\${APP_URL}|${host_name}|g" -e "s|\${SERVE_ROOT}|${serve_root}|g" "$BACKEND_CONFIG_DIR/template.conf" > "$site_conf"

        db_exists "$db" || { log "Creating missing DB: $db"; db_create "$host_name"; }
    done

    info "Finished building web configs. Restarting Caddy..."
    $DC restart franken_php
}

supervisor_generate_conf() {
    local host="$1"; require_host "$host" "supervisor-conf"
    local host_underscored="${host//./_}" output_dir="${2:-/etc/supervisor/conf.d}" log_dir="/tmp/supervisor-logs/$host"
    sudo mkdir -p "$log_dir"
    sudo tee "$output_dir/${host_underscored}.conf" >/dev/null <<-EOF
	[program:$host_underscored]
	process_name=%(program_name)s_%(process_num)02d
	command=php $WEB_ROOT/$host/artisan horizon
	autostart=true
	autorestart=true
	stopasgroup=true
	killasgroup=true
	user=$USERNAME
	numprocs=1
	redirect_stderr=true
	stdout_logfile=$log_dir/worker.log
	stopwaitsecs=3600
	EOF
    info "Supervisor config generated at $output_dir/${host_underscored}.conf"
}

supervisor_restart() {
    systemctl is-enabled --quiet supervisor || sudo systemctl enable --now supervisor
    sudo systemctl restart supervisor
    sudo supervisorctl restart all
}

scaffold_wordpress() {
    local host="$1" archive="$WEB_ROOT/wordpress.tar.gz" project_path="$WEB_ROOT/$host"
    require_cmd curl; require_cmd tar
    [[ -d "$project_path" ]] && { warn "WordPress $project_path already exists."; return 1; }
    [[ -f "$archive" ]] || curl -fSL https://en-gb.wordpress.org/latest-en_GB.tar.gz -o "$archive"
    local tmp_dir; tmp_dir=$(mktemp -d)
    info "Extracting WordPress"
    tar -xzf "$archive" -C "$tmp_dir"
    mkdir -p "$project_path"
    mv "$tmp_dir/wordpress/"* "$project_path"
    rm -rf "$tmp_dir"
    local db_name dest_conf
    db_name=$(make_db_name "$host" "wp")
    dest_conf="$project_path/wp-config.php"
    [[ ! -f "$dest_conf" ]] && mv "$project_path/wp-config-sample.php" "$dest_conf"
    sed -i "s/username_here/root/g;s/database_name_here/$db_name/g;s/password_here/secret/g;s/localhost/mariadb/g" "$dest_conf"
}

scaffold_laravel() {
    local host="$1" project_path="$WEB_ROOT/$host"
    [[ -d "$project_path" ]] && { warn "Laravel project $project_path already exists."; return 1; }
    mkdir -p "$project_path"
    composer create-project --prefer-dist laravel/laravel "$project_path"
}

new_host() {
    local host="$1" host_type="$2"
    require_docker; ensure_jq; require_host "$host" "new-host"
    local db_name; db_name=$(make_db_name "$host" "$host_type")
    case "$host_type" in
        wp|wordpress) scaffold_wordpress "$host" ;;
        laravel)      supervisor_generate_conf "$host"; scaffold_laravel "$host" ;;
        *)            die "Invalid type '$host_type'. Use: wp, wordpress, or laravel." ;;
    esac
    hosts_json_add "$host" "$host_type" "$db_name"
    redirect_add "$host"
    build_webconf
}

remove_host() {
    local host="$1"; require_host "$host" "remove-host"
    local db_name; db_name=$(hosts_json_get_db "$host")
    [[ -n "$db_name" ]] && db_remove "$host"
    log "Removing $WEB_ROOT/$host"
    rm -rf "${WEB_ROOT:?}/$host"
    redirect_remove "$host"
    hosts_json_remove "$host"
    build_webconf
}

dc_build() {
    local service="${1:-}" cache_flag="${2:-}"
    [[ "$cache_flag" == "--no-cache" ]] || cache_flag=""
    if [[ -z "$service" ]]; then
        log "Building all services..."
        $DC build $cache_flag && $DC up -d --force-recreate
    else
        log "Building service: $service"
        $DC build $cache_flag "$service" && $DC up -d --force-recreate "$service"
    fi
}

parse_new_host_args() {
    HOST="" ; TYPE="wp"
    while [[ $# -gt 0 ]]; do
        case "$1" in -t) TYPE="${2:-}"; shift 2 ;; *) HOST="$1"; shift ;; esac
    done
    require_host "$HOST" "new-host <hostname> -t <wp|laravel>"
}

show_help() {
    cat <<'EOF'
web.sh - Docker PHP development environment

Usage: web <command> [options]

Environment:
  up [service]                  Start Docker services
  down                          Stop and remove services
  stop [service]                Stop services
  restart [service]             Restart services
  build [service] [--no-cache]  Build services
  ps [service]                  Container status
  log <service>                 View service logs

Hosts:
  new-host <host> [-t type]     Create site (wp|laravel)
  remove-host <host>            Remove site completely
  build-webconf                 Regenerate Caddy configs

Shell:
  bash                          Container Bash
  fish                          Container Fish

SSL:
  rootssl                       Generate root CA
  hostssl <host>                Generate host SSL
  import-rootca                 Import root CA to Chrome

Tools:
  redis-flush                   Flush Redis
  redis-monitor                 Monitor Redis
  debug <off|debug|profile>     Set Xdebug mode
  supervisor-conf <host>        Generate Supervisor config
  supervisor-restart            Restart Supervisor
  install                       Create CLI symlinks
  dir                           Print script directory
  git-update <user> <theme> [plugin]  Git pull on lyntouch.com
EOF
}

main() {
    local cmd="${1:-help}"; shift 2>/dev/null || true
    case "$cmd" in
        up)               $DC up -d "$@" ;;
        down)             $DC down ;;
        stop)             $DC stop "$@" ;;
        restart)          $DC restart "$@" ;;
        build)            dc_build "$@" ;;
        ps)               $DC ps "$@" ;;
        log)              $DC logs -f "$@" ;;
        new-host)         parse_new_host_args "$@"; new_host "$HOST" "$TYPE" ;;
        remove-host)      parse_new_host_args "$@"; confirm "Remove $HOST?" && remove_host "$HOST" ;;
        build-webconf)    build_webconf ;;
        bash)             $DC exec franken_php bash ;;
        fish)             $DC exec franken_php fish ;;
        rootssl)          ssl_generate_root; $DC restart franken_php ;;
        hostssl)          require_host "${1:-}" "hostssl"; ssl_generate_host "$1" ;;
        import-rootca)    ssl_import_root_to_chrome "$ROOT_CRT" ;;
        redis-flush)      $DC exec redis redis-cli flushall ;;
        redis-monitor)    $DC exec redis redis-cli monitor ;;
        debug)            [[ -z "${1:-}" ]] && die "Usage: web debug <off|debug|profile>"
                          sed -i "s/XDEBUG_MODE=.*/XDEBUG_MODE=$1/" "$SCRIPT_DIR/.env"; $DC up -d franken_php ;;
        supervisor-conf)    supervisor_generate_conf "${1:-}" ;;
        supervisor-restart) supervisor_restart ;;
        install)          ln -sf "$SCRIPT_DIR/web.sh" "$HOME/.local/bin/web"
                          ln -sf "$SCRIPT_DIR/web.completions.fish" "$HOME/.config/fish/completions/web.fish"
                          info "Symlinks created." ;;
        dir)              echo "$SCRIPT_DIR" ;;
        git-update)       local user="${1:-}" theme="${2:-}" plugin="${3:-lyntouch-modules}"
                          [[ -z "$theme" ]] && die "Usage: web git-update <user> <theme> [plugin]"
                          ssh "${user}@lyntouch.com" "git -C public_html/wp-content/plugins/${plugin} pull; git -C public_html/wp-content/themes/${theme} pull" ;;
        *)                show_help ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi

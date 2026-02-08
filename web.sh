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
ROOT_KEY="$CERTS_DIR/rootCA.key" ROOT_CRT="$CERTS_DIR/rootCA.crt"
DC="docker compose -f $SCRIPT_DIR/docker-compose.yml"
SUPERVISOR_DIR="${SUPERVISOR_DIR:-$HOME/supervisor}"
KNOWN_SLDS="co.uk gov.uk com.br co.jp"
_HOSTS_MODULE_PATH_CACHED="" _IS_WSL=""

_has_gum() { command -v gum &>/dev/null; }
die()  { if _has_gum; then gum log --level error "$1" >&2; else printf '\033[31mError: %s\033[0m\n' "$1" >&2; fi; exit 1; }
warn() { if _has_gum; then gum log --level warn "$1" >&2; else printf '\033[0;33m%s\033[0m\n' "$1" >&2; fi; }
info() { if _has_gum; then gum log --level info "$1"; else printf '\033[0;32m%s\033[0m\n' "$1"; fi; }
log()  { if _has_gum; then gum log --level debug "$1"; else printf '%s\n' "$1"; fi; }
spin() { if _has_gum; then gum spin --spinner dot --title "$1" -- "${@:2}"; else log "$1"; "${@:2}"; fi; }

require_cmd()    { command -v "$1" &>/dev/null || die "$1 is not installed."; }
require_host()   { [[ -n "${1:-}" ]] || die "No hostname specified. Usage: web $2 <hostname>"; }
require_docker() { require_cmd docker; docker info &>/dev/null || die "Docker daemon is not running."; }
ensure_jq()      { command -v jq &>/dev/null || { log "Installing jq..."; sudo apt update && sudo apt install -y jq; }; }
ensure_gum() {
    command -v gum &>/dev/null && return 0
    log "Installing gum..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
    sudo apt update && sudo apt install -y gum
}

confirm()       { ensure_gum && gum confirm "$1"; }
select_option() { local prompt="$1"; shift; ensure_gum && gum choose --header="$prompt" "$@"; }
prompt_input()  { ensure_gum && gum input --prompt="$1: " --value="${2:-}"; }

dc_action() {
    local action="$1"; shift
    local services=("$@")
    local action_label spin_label

    case "$action" in
        up)      action_label="Starting"  ; spin_label="Starting services..."  ;;
        down)    action_label="Stopping"  ; spin_label="Stopping services..."  ;;
        stop)    action_label="Stopping"  ; spin_label="Stopping services..."  ;;
        restart) action_label="Restarting"; spin_label="Restarting services..." ;;
        *)       action_label="Running"   ; spin_label="Running $action..."    ;;
    esac

    # resolve which services are targeted
    if [[ ${#services[@]} -eq 0 ]]; then
        mapfile -t services < <($DC config --services 2>/dev/null)
    fi

    # display the service list
    if _has_gum; then
        local svc_list=""
        for svc in "${services[@]}"; do svc_list+="  • $svc"$'\n'; done
        gum style --bold --foreground 212 "$action_label:"
        printf '%s' "$svc_list"
    else
        log "$action_label: ${services[*]}"
    fi

    # run the docker compose command
    case "$action" in
        up)   spin "$spin_label" $DC up -d "${services[@]}" ;;
        down) spin "$spin_label" $DC down ;;
        *)    spin "$spin_label" $DC "$action" "${services[@]}" ;;
    esac

    # show status after the action (except down which removes containers)
    if [[ "$action" != "down" ]]; then
        echo ""
        dc_ps "${services[@]}"
    fi
}

dc_ps() {
    if ! _has_gum; then $DC ps "$@"; return; fi

    local json_lines
    json_lines=$($DC ps --format json "$@" 2>/dev/null) || { $DC ps "$@"; return; }
    [[ -z "$json_lines" ]] && { info "No containers running."; return; }

    local SEP=$'\t' table_rows=""
    while IFS= read -r line; do
        local svc state health status image ports tcp_ports udp_ports indicator
        svc=$(echo "$line" | jq -r '.Service')
        state=$(echo "$line" | jq -r '.State')
        health=$(echo "$line" | jq -r '.Health // ""')
        status=$(echo "$line" | jq -r '.Status')
        image=$(echo "$line" | jq -r '.Image')
        tcp_ports=$(echo "$line" | jq -r \
            '[.Publishers[] | select(.URL == "0.0.0.0" and .PublishedPort > 0 and .Protocol == "tcp") | .PublishedPort] | unique | sort | map(tostring) | join(",")')
        udp_ports=$(echo "$line" | jq -r \
            '[.Publishers[] | select(.URL == "0.0.0.0" and .PublishedPort > 0 and .Protocol == "udp") | .PublishedPort] | unique | sort | map(tostring) | join(",")')

        if [[ -n "$tcp_ports" && -n "$udp_ports" ]]; then
            ports="tcp: $tcp_ports | udp: $udp_ports"
        elif [[ -n "$tcp_ports" ]]; then
            ports="tcp: $tcp_ports"
        elif [[ -n "$udp_ports" ]]; then
            ports="udp: $udp_ports"
        else
            ports="-"
        fi

        if [[ "$state" == "running" ]]; then
            if [[ "$health" == "healthy" || -z "$health" ]]; then indicator="🟢"; else indicator="🟡"; fi
        elif [[ "$state" == "exited" || "$state" == "dead" ]]; then
            indicator="🔴"
        else
            indicator="⚪"
        fi

        table_rows+="${indicator} ${svc}${SEP}${image}${SEP}${status}${SEP}${ports}"$'\n'
    done <<< "$json_lines"

    printf '%s\n' "SERVICE${SEP}IMAGE${SEP}STATUS${SEP}PORTS" | cat - <(printf '%s' "$table_rows") \
        | gum table --print --separator "$SEP" --border rounded \
            --border.foreground 240 \
            --header.foreground 39 \
            --padding "0 1"
}

new_host_wizard() {
    HOST=$(prompt_input "Hostname" "")
    TYPE=$(select_option "Site type:" "wp" "laravel")
    local default_db; default_db=$(make_db_name "$HOST" "$TYPE")
    DB_NAME=$(prompt_input "Database name" "$default_db")
    local with_supervisor=false
    [[ "$TYPE" == "laravel" ]] && confirm "Generate Supervisor config?" && with_supervisor=true
    echo ""
    log "Hostname:   $HOST"
    log "Type:       $TYPE"
    log "Database:   $DB_NAME"
    [[ "$TYPE" == "laravel" ]] && log "Supervisor: $with_supervisor"
    echo ""
    confirm "Proceed?" || { warn "Aborted."; return 1; }
    new_host "$HOST" "$TYPE" "$DB_NAME" "$with_supervisor"
}

is_wsl() {
    [[ -z "$_IS_WSL" ]] && { grep -q WSL /proc/version 2>/dev/null && _IS_WSL=1 || _IS_WSL=0; }
    ((_IS_WSL))
}

powershell_exe() { command -v pwsh.exe &>/dev/null && echo "pwsh.exe" || echo "powershell.exe"; }

hosts_json_query()    { jq "$@" "$HOSTS_JSON"; }
hosts_json_get_host() { hosts_json_query -r --arg hn "$1" '.hosts[] | select(.name == $hn)'; }
hosts_json_get_db()   { hosts_json_query -r --arg hn "$1" '.hosts[] | select(.name == $hn) | .db'; }

hosts_json_add() {
    local host_name="$1" host_type="$2" db_name="$3"
    [[ -n "$(hosts_json_get_host "$host_name")" ]] && { warn "Host $host_name already exists."; return 1; }
    local tmp; tmp=$(mktemp)
    jq --arg hn "$host_name" --arg ht "$host_type" --arg db "$db_name" \
        '.hosts += [{name: $hn, type: $ht, db: $db}]' "$HOSTS_JSON" > "$tmp" && mv "$tmp" "$HOSTS_JSON"
}

hosts_json_remove() {
    local tmp; tmp=$(mktemp)
    jq --arg hn "$1" 'del(.hosts[] | select(.name == $hn))' "$HOSTS_JSON" > "$tmp" && mv "$tmp" "$HOSTS_JSON"
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
    local -a parts; IFS='.' read -r -a parts <<< "$1"
    local n=${#parts[@]}
    ((n <= 1)) && { echo "$1"; return; }
    local tld_count=1 last_two="${parts[n-2]}.${parts[n-1]}" sld
    for sld in $KNOWN_SLDS; do [[ "$last_two" == "$sld" ]] && { tld_count=2; break; }; done
    local idx=$((n - tld_count - 1))
    ((idx < 0)) && idx=0
    echo "${parts[idx]}"
}

sanitize_db_identifier() {
    local c="${1//[^A-Za-z0-9_]/_}"
    while [[ "$c" == _* ]]; do c="${c#_}"; done
    [[ -z "$c" ]] && c="db"
    [[ "$c" =~ ^[0-9] ]] && c="db_${c}"
    echo "$c"
}

make_db_name() {
    local host="$1" host_type="$2"
    local -a parts; IFS='.' read -r -a parts <<< "$host"
    local n=${#parts[@]} main_domain sub_domain="" tld_count=1

    if ((n <= 1)); then
        main_domain="$host"
    else
        ((n >= 2)) && ((${#parts[n-2]} <= 3)) && tld_count=2
        local idx=$((n - 1 - tld_count))
        ((idx < 0)) && idx=0
        main_domain="${parts[idx]}"
        if ((idx > 0)); then
            sub_domain="${parts[0]}"
            for ((i = 1; i < idx; i++)); do sub_domain="${sub_domain}.${parts[i]}"; done
        fi
    fi

    local db_name
    [[ -z "$sub_domain" || "$sub_domain" == "$main_domain" ]] \
        && db_name="$main_domain" \
        || db_name="${main_domain}_${sub_domain//./_}"
    case "$host_type" in wordpress|wp) db_name="${db_name}_wp" ;; *) db_name="${db_name}_db" ;; esac
    sanitize_db_identifier "${db_name//./_}"
}

db_create() {
    local db; db=$(hosts_json_get_db "$1")
    [[ -z "$db" ]] && die "No database configured for host $1"
    log "Creating database and user: $db"
    $DC exec -T mariadb mariadb -uroot -psecret -e \
        "CREATE USER IF NOT EXISTS '${db}'@'%' IDENTIFIED BY 'secret'; \
         CREATE DATABASE IF NOT EXISTS \`${db}\`; \
         GRANT ALL PRIVILEGES ON \`${db}\`.* TO '${db}'@'%';" </dev/null
}

db_remove() {
    local db; db=$(hosts_json_get_db "$1")
    [[ -z "$db" ]] && return 0
    log "Removing database and user: $db"
    $DC exec -T mariadb mariadb -uroot -psecret -e \
        "DROP DATABASE IF EXISTS \`${db}\`; DROP USER IF EXISTS '${db}'@'%';" </dev/null
}

db_exists() {
    [[ -n "$($DC exec -T mariadb mariadb -uroot -psecret -Nse \
        "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='$1'" </dev/null)" ]]
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
    local filename="${1:-rootCA}" passphrase="${2:-default}" days=29200
    local subj="/C=GB/ST=London/L=London/O=Lyntouch/OU=IT Department/CN=Lyntouch Self-Signed RootCA/emailAddress=info@lyntouch.com"
    local expiry; expiry=$(date -d "+${days} days" "+%Y-%m-%d") || die "Failed to calculate expiry date."
    mkdir -p "$CERTS_DIR"
    local key="$CERTS_DIR/${filename}.key" crt="$CERTS_DIR/${filename}.crt"
    log "Creating Root CA: $key (expires $expiry)"
    openssl genrsa -des3 -passout "pass:$passphrase" -out "$key" 4096 || return 1
    openssl req -x509 -new -nodes -passin "pass:$passphrase" -key "$key" -sha256 -days "$days" -subj "$subj" -out "$crt" || return 1
    info "Root CA created successfully"
}

ssl_generate_host() {
    local h="$1" subj="/C=GB/ST=London/L=London/O=$1/OU=IT Department/CN=Lyntouch Self-Signed Host Certificate/emailAddress=info@lyntouch.com"
    local crt="$CERTS_DIR/$h.crt" key="$CERTS_DIR/$h.key" csr="$CERTS_DIR/$h.csr"
    [[ -f "$key" ]] || { info "Generating SSL key for $h"
        openssl req -new -sha256 -nodes -out "$csr" -newkey rsa:2048 -subj "$subj" -keyout "$key"; }
    [[ -f "$crt" ]] || { info "Generating SSL certificate for $h"
        openssl x509 -req -passin pass:default -in "$csr" -CA "$ROOT_CRT" -CAkey "$ROOT_KEY" \
            -CAcreateserial -out "$crt" -days 500 -sha256 -extfile <(ssl_extfile "$h"); }
}

ssl_import_root_to_chrome() {
    is_wsl && die "Chrome root CA import is not supported on WSL."
    local cert="${1:-$ROOT_CRT}" nick="${2:-Root CA}"
    [[ -f "$cert" ]] || die "Certificate file not found: $cert"
    openssl x509 -outform der -in "$cert" -out "${cert}.der"
    local db="$HOME/.pki/nssdb"
    [[ -d "$db" ]] || { mkdir -p "$db"; certutil -N -d "$db"; }
    certutil -d "sql:$db" -A -t "C,," -n "$nick" -i "${cert}.der"
    info "Certificate imported to Chrome with nickname: $nick"
}

_resolve_hosts_module_path() {
    [[ -n "$_HOSTS_MODULE_PATH_CACHED" ]] && { echo "$_HOSTS_MODULE_PATH_CACHED"; return 0; }
    local paths=(
        "/mnt/c/Users/*/Documents/PowerShell/Modules/Hosts/*/Hosts.psd1"
        "/mnt/c/Users/*/Documents/WindowsPowerShell/Modules/Hosts/*/Hosts.psd1"
        "/mnt/c/Users/*/Documents/PowerShell/Modules/Hosts/*/Hosts.psm1"
        "/mnt/c/Users/*/Documents/WindowsPowerShell/Modules/Hosts/*/Hosts.psm1"
    )
    shopt -s nullglob
    for p in "${paths[@]}"; do
        for m in $p; do _HOSTS_MODULE_PATH_CACHED="$m"; break 2; done
    done
    shopt -u nullglob
    echo "$_HOSTS_MODULE_PATH_CACHED"
}

_run_host_mapping_cmdlet() {
    local cmdlet="$1" hostname="$2" module_path import_cmd
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
        local escaped="${host//./\\.}"
        grep -qP "^\s*127\.0\.0\.1.*${escaped}(?:\s+|$)" "/mnt/c/Windows/System32/drivers/etc/hosts" 2>/dev/null && return 0
        log "Adding host redirection for \"$host\""
        _run_host_mapping_cmdlet "New-HostnameMapping" "$host" || { warn "Failed to add host mapping for $host."; return 1; }
    else
        getent hosts "$host" &>/dev/null && return 0
        log "Adding host redirection for \"$host\""
        echo "127.0.0.1 $host" | sudo tee -a /etc/hosts >/dev/null
    fi
}

redirect_remove() {
    local host="$1" escaped
    log "Removing host redirection for \"$host\""
    if is_wsl; then
        _run_host_mapping_cmdlet "Remove-HostnameMapping" "$host" || { warn "Failed to remove host mapping for $host."; return 1; }
    else
        escaped="${host//./\\.}"
        grep -q "$escaped" /etc/hosts 2>/dev/null && sudo sed -i.bak "/$escaped/d" /etc/hosts
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
    local host_name host_type db serve_root
    while IFS=$'\t' read -r host_name host_type db; do
        log "Processing host: $host_name"
        serve_root="/var/www/$host_name"

        [[ "$host_type" == wp || "$host_type" == wordpress ]] && \
            echo "* * * * * cd $serve_root && php $serve_root/wp-cron.php >/proc/self/fd/1 2>/proc/self/fd/2" >> "$SCRIPT_DIR/crontab"

        redirect_add "$host_name"
        ssl_generate_host "$host_name"
        [[ "$host_type" == "laravel" ]] && serve_root="$serve_root/public"

        local debugout="$WEB_ROOT/$host_name/.vscode"
        mkdir -p "$debugout"
        sed -e "s|\${HOSTNAME}|$host_name|g" "$SCRIPT_DIR/launch.json" > "$debugout/launch.json"
        sed -e "s|\${APP_URL}|${host_name}|g" -e "s|\${SERVE_ROOT}|${serve_root}|g" "$BACKEND_CONFIG_DIR/template.conf" > "$BACKEND_SITES_DIR/${host_name}.conf"

        db_exists "$db" || { log "Creating missing DB: $db"; db_create "$host_name"; }
    done < <(hosts_json_query -r '.hosts[] | [.name, .type, .db] | @tsv')

    info "Finished building web configs. Restarting Caddy..."
    spin "Restarting Caddy..." $DC restart franken_php
}

supervisor_init() {
    [[ -f "$SUPERVISOR_DIR/supervisord.conf" ]] && return 0
    mkdir -p "$SUPERVISOR_DIR"/{conf.d,logs}
    cat > "$SUPERVISOR_DIR/supervisord.conf" <<-EOF
	[unix_http_server]
	file=$SUPERVISOR_DIR/supervisor.sock
	
	[supervisord]
	logfile=$SUPERVISOR_DIR/logs/supervisord.log
	pidfile=$SUPERVISOR_DIR/supervisord.pid
	
	[rpcinterface:supervisor]
	supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface
	
	[supervisorctl]
	serverurl=unix://$SUPERVISOR_DIR/supervisor.sock
	
	[include]
	files = $SUPERVISOR_DIR/conf.d/*.conf
	EOF
    info "Supervisor initialized at $SUPERVISOR_DIR"
}

supervisor_generate_conf() {
    local host="$1"; require_host "$host" "supervisor-conf"
    supervisor_init
    local hu="${host//./_}" outdir="${2:-$SUPERVISOR_DIR/conf.d}" logdir="$SUPERVISOR_DIR/logs"
    cat > "$outdir/${hu}.conf" <<-EOF
	[program:$hu]
	process_name=%(program_name)s_%(process_num)02d
	command=php $WEB_ROOT/$host/artisan horizon
	autostart=true
	autorestart=true
	stopasgroup=true
	killasgroup=true
	numprocs=1
	redirect_stderr=true
	stdout_logfile=$logdir/${hu}.log
	stopwaitsecs=3600
	EOF
    info "Supervisor config generated at $outdir/${hu}.conf"
}

supervisor_restart() {
    supervisor_init
    if [[ -f "$SUPERVISOR_DIR/supervisord.pid" ]] && kill -0 "$(cat "$SUPERVISOR_DIR/supervisord.pid")" 2>/dev/null; then
        supervisorctl -c "$SUPERVISOR_DIR/supervisord.conf" reread
        supervisorctl -c "$SUPERVISOR_DIR/supervisord.conf" update
    else
        supervisord -c "$SUPERVISOR_DIR/supervisord.conf"
    fi
}

scaffold_wordpress() {
    local host="$1" db_name="$2" archive="$WEB_ROOT/wordpress.tar.gz" path="$WEB_ROOT/$host"
    require_cmd curl; require_cmd tar
    [[ -d "$path" ]] && { warn "WordPress $path already exists."; return 1; }
    [[ -f "$archive" ]] || curl -fSL https://en-gb.wordpress.org/latest-en_GB.tar.gz -o "$archive"
    local tmp; tmp=$(mktemp -d)
    info "Extracting WordPress"
    tar -xzf "$archive" -C "$tmp"
    mkdir -p "$path" && mv "$tmp/wordpress/"* "$path" && rm -rf "$tmp"
    local conf="$path/wp-config.php"
    [[ ! -f "$conf" ]] && mv "$path/wp-config-sample.php" "$conf"
    sed -i "s/username_here/root/g;s/database_name_here/$db_name/g;s/password_here/secret/g;s/localhost/mariadb/g" "$conf"
}

scaffold_laravel() {
    local host="$1" db_name="$2" path="$WEB_ROOT/$host"
    [[ -d "$path" ]] && { warn "Laravel project $path already exists."; return 1; }
    composer create-project --prefer-dist laravel/laravel "$path"
    sed -i \
        -e "s|APP_URL=.*|APP_URL=https://$host|" \
        -e "s|^DB_CONNECTION=.*|DB_CONNECTION=mysql|" \
        -e "s|^# DB_HOST=.*|DB_HOST=mariadb|" \
        -e "s|^# DB_PORT=.*|DB_PORT=3306|" \
        -e "s|^# DB_DATABASE=.*|DB_DATABASE=$db_name|" \
        -e "s|^# DB_USERNAME=.*|DB_USERNAME=$db_name|" \
        -e "s|^# DB_PASSWORD=.*|DB_PASSWORD=secret|" \
        "$path/.env"
}

new_host() {
    local host="$1" host_type="$2" db_name="${3:-}" with_supervisor="${4:-true}"
    require_docker; ensure_jq; require_host "$host" "new-host"
    [[ -z "$db_name" ]] && db_name=$(make_db_name "$host" "$host_type")
    case "$host_type" in
        wp|wordpress) scaffold_wordpress "$host" "$db_name" ;;
        laravel)      scaffold_laravel "$host" "$db_name"
                      [[ "$with_supervisor" == "true" ]] && supervisor_generate_conf "$host" ;;
        *)            die "Invalid type '$host_type'. Use: wp, wordpress, or laravel." ;;
    esac
    hosts_json_add "$host" "$host_type" "$db_name"
    redirect_add "$host"
    build_webconf
    [[ "$host_type" == "laravel" ]] && $DC exec -T franken_php php "/var/www/$host/artisan" migrate --force </dev/null
}

remove_host() {
    local host="$1" hu; require_host "$host" "remove-host"
    hu="${host//./_}"
    [[ -n "$(hosts_json_get_db "$host")" ]] && db_remove "$host"
    log "Removing $WEB_ROOT/$host"
    rm -rf "${WEB_ROOT:?}/$host"
    rm -f "$CERTS_DIR/$host".{key,crt,csr}
    rm -f "$SUPERVISOR_DIR/conf.d/${hu}.conf"
    redirect_remove "$host"
    hosts_json_remove "$host"
}

remove_host_interactive() {
    ensure_gum
    local hosts
    hosts=$(hosts_json_query -r '.hosts[].name' 2>/dev/null)
    [[ -z "$hosts" ]] && die "No hosts configured."

    local selected
    selected=$(printf '%s\n' "$hosts" | gum choose --no-limit --header="Select hosts to remove (space to toggle, enter to confirm)") \
        || { warn "No hosts selected."; return 1; }
    [[ -z "$selected" ]] && { warn "No hosts selected."; return 1; }

    echo ""
    log "The following hosts will be removed:"
    printf '  - %s\n' $selected
    echo ""
    confirm "Proceed with removal?" || { warn "Aborted."; return 1; }

    local host
    while IFS= read -r host; do
        [[ -n "$host" ]] && remove_host "$host"
    done <<< "$selected"
    build_webconf
}

dc_build() {
    local svc="${1:-}" cache="${2:-}"
    [[ "$cache" == "--no-cache" ]] || cache=""
    log "Building ${svc:-all services}..."
    $DC build $cache $svc && spin "Recreating containers..." $DC up -d --force-recreate $svc
}

parse_new_host_args() {
    HOST="" ; TYPE="wp"
    while [[ $# -gt 0 ]]; do
        case "$1" in -t) [[ -n "${2:-}" ]] || die "Option -t requires a value (wp or laravel)."; TYPE="$2"; shift 2 ;; *) HOST="$1"; shift ;; esac
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
  new-host [host] [-t type]     Create site (interactive wizard or flags)
  remove-host [host]            Remove site (interactive multi-select or by name)
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
  debug [off|debug|profile]     Set Xdebug mode (interactive if omitted)
  supervisor-init                Initialize user-level Supervisor
  supervisor-conf <host>        Generate Supervisor config
  supervisor-restart            Start/reload Supervisor
  install                       Create CLI symlinks
  dir                           Print script directory
  git-update <user> <theme> [plugin]  Git pull on lyntouch.com
EOF
}

main() {
    local cmd="${1:-help}"; shift 2>/dev/null || true
    case "$cmd" in
        up)               dc_action up "$@" ;;
        down)             dc_action down ;;
        stop)             dc_action stop "$@" ;;
        restart)          dc_action restart "$@" ;;
        build)            dc_build "$@" ;;
        ps)               dc_ps "$@" ;;
        log)              $DC logs -f "$@" ;;
        new-host)         if [[ $# -eq 0 ]]; then new_host_wizard
                          else parse_new_host_args "$@"; new_host "$HOST" "$TYPE"; fi ;;
        remove-host)      if [[ $# -eq 0 ]]; then remove_host_interactive
                          else parse_new_host_args "$@"; confirm "Remove $HOST?" && { remove_host "$HOST"; build_webconf; }; fi ;;
        build-webconf)    build_webconf ;;
        bash)             $DC exec franken_php bash ;;
        fish)             $DC exec franken_php fish ;;
        rootssl)          ssl_generate_root; spin "Restarting Caddy..." $DC restart franken_php ;;
        hostssl)          require_host "${1:-}" "hostssl"; ssl_generate_host "$1" ;;
        import-rootca)    ssl_import_root_to_chrome "$ROOT_CRT" ;;
        redis-flush)      $DC exec redis redis-cli flushall ;;
        redis-monitor)    $DC exec redis redis-cli monitor ;;
        debug)            local mode="${1:-}"
                          [[ -z "$mode" ]] && mode=$(select_option "Xdebug mode:" "off" "debug" "profile")
                          sed -i "s/XDEBUG_MODE=.*/XDEBUG_MODE=$mode/" "$SCRIPT_DIR/.env"; spin "Applying Xdebug mode: $mode..." $DC up -d franken_php ;;
        supervisor-init)  supervisor_init ;;
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

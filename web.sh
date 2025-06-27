#!/bin/bash

set -o errexit

CMD="${1:-false}"
HOST="${2:-false}"
DEST="${3:-false}"

WEB_ROOT=${WEB_ROOT:-$HOME/www}
USERNAME=${USERNAME:-$(whoami)}
SCRIPT_DIR=${SCRIPT_DIR:-$HOME/www/dev}
BACKEND_DIR=${BACKEND_DIR:-$SCRIPT_DIR/franken_php}
BACKEND_CONFIG_DIR=$BACKEND_DIR/config
BACKEND_SITES_DIR=$BACKEND_CONFIG_DIR/sites
DC="docker compose -f $SCRIPT_DIR/docker-compose.yml"

CERTS_DIR="$BACKEND_CONFIG_DIR/ssl"
ROOT_KEY="$CERTS_DIR/rootCA.key"
ROOT_CRT="$CERTS_DIR/rootCA.crt"

function add_host_config {
    host_type="${1:-wordpress}"
    parts=($(echo "$HOST" | tr '.' ' '))
    n=${#parts[@]}

    if ((n <= 1)); then
        main_domain="$HOST"
        sub_domain=""
        root_domain="$HOST"
    else
        tld_count=1
        if ((n >= 2)) && ((${#parts[n - 2]} <= 3)); then
            tld_count=2
        fi
        tld="${parts[n - tld_count]}"
        for ((i = n - tld_count + 1; i < n; i++)); do
            tld="$tld.${parts[i]}"
        done
        main_idx=$((n - 1 - tld_count))
        main_domain="${parts[main_idx]}"
        sub_domain=""
        if ((main_idx > 0)); then
            sub_domain="${parts[0]}"
            for ((i = 1; i < main_idx; i++)); do
                sub_domain="$sub_domain.${parts[i]}"
            done
        fi
        root_domain="$main_domain.$tld"
    fi

    if [[ -z "$sub_domain" || "$sub_domain" == "$main_domain" ]]; then
        db_name="$main_domain"
    else
        db_name="${main_domain}_$(echo "$sub_domain" | tr '.' '_')"
    fi

    if [[ "$host_type" == "wordpress" || "$host_type" == "wp" ]]; then
        db_name="${db_name}_wp"
    else
        db_name="${db_name}_db"
    fi
    db_name="$(echo "$db_name" | tr '.' '_')"

    json_file="$WEB_ROOT/dev/web-hosts.json"

    existing_host=$(jq -r --arg hn "$HOST" '.hosts[] | select(.name == $hn)' $json_file)
    if [ -n "$existing_host" ]; then
        echo "Host $HOST already exists in the JSON file." >&2
        return 1
    fi

    new_host=$(jq -n \
        --arg hn "$HOST" \
        --arg ht "$host_type" \
        --arg db "$db_name" \
        '{name: $hn, type: $ht, db: $db}')

    jq ".hosts += [$new_host]" $json_file >"temp.json" && mv "temp.json" $json_file
}

function build_webconf {
    config_path="$SCRIPT_DIR/web-hosts.json"
    yaml_file="$SCRIPT_DIR/templates.yml"
    find "$BACKEND_CONFIG_DIR/sites" -type f ! -name 'phpmyadmin.test.conf' ! -name '.gitkeep' -delete

    if [ ! -f "$config_path" ]; then
        echo "No config file found, creating default one"
        echo '{
            "output": "'$BACKEND_SITES_DIR'",
            "template": "'$BACKEND_CONFIG_DIR/template.conf'",
            "WEB_ROOT": "'$WEB_ROOT'",
            "hosts": []
        }' >"$config_path"
        exit 1
    fi

    if ! jq -e '.hosts[] | select(.name == "phpmyadmin.test")' "$config_path"; then
        add_host_redirect "phpmyadmin.test"
        add_host_ssl "phpmyadmin.test"
    fi

    echo "services:" >"$yaml_file"
    echo "  franken_php:" >>"$yaml_file"
    echo "    networks:" >>"$yaml_file"
    echo "      dev_network:" >>"$yaml_file"
    echo "        aliases:" >>"$yaml_file"

    for row in $(jq -c '.hosts[]' "$config_path"); do
        host_name=$(echo "$row" | jq -r '.name')
        echo "          - $host_name" >>"$yaml_file"
    done

    echo "" >"$SCRIPT_DIR/crontab"

    mapfile -t host_entries < <(jq -c '.hosts[]' "$config_path")
    for row in "${host_entries[@]}"; do
        {
            host_name=$(echo "$row" | jq -r '.name')
            type=$(echo "$row" | jq -r '.type')
            db=$(echo "$row" | jq -r '.db')
            host_name_root=$(hostname_root "$host_name")

            echo "🔧 Processing host: $host_name"

            serve_root="/var/www/$host_name"
            site_conf="$BACKEND_SITES_DIR/$host_name.conf"
            debugout="$HOME/www/$host_name/.vscode"

            if [[ "$type" == "wp" || "$type" == "wordpress" ]]; then
                echo "* * * * * cd $serve_root && php $serve_root/wp-cron.php >/proc/self/fd/1 2>/proc/self/fd/2" >>"$SCRIPT_DIR/crontab"
            fi

            add_host_redirect "$host_name"
            add_host_ssl "$host_name"

            [[ "$type" == "laravel" ]] && serve_root="$serve_root/public"

            mkdir -p "$debugout"
            sed -e "s|\${HOSTNAME}|$host_name|g;" "$SCRIPT_DIR/launch.json" >"$debugout/launch.json"
            sed -e "s|\${APP_URL}|${host_name}|g;" -e "s|\${SERVE_ROOT}|${serve_root}|g;" \
                "$BACKEND_CONFIG_DIR/template.conf" >"$site_conf"

            DB_EXISTS=$(docker exec dev-mariadb-1 mariadb -u root -psecret -Nse \
                "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='${db}'")

            if [ -z "$DB_EXISTS" ]; then
                echo "📦 Creating missing DB: ${db}"
                db_cmd create $host_name
            fi
        } || {
            echo "❌ Error processing host: $host_name. Skipping..."
            continue
        }
    done

    echo "✅ Finished Building Web Configs. Restarting Caddy..."
    $DC restart franken_php
}

function check_host {
    if [ -z "$HOST" ]; then
        echo "No HOST parameter specified"
        exit 1
    fi
}

function confirm_action {
    read -p "$1 [Y/N]" -n 1 -r REPLY
    echo ""
    case $REPLY in
    [Yy]*)
        return 0
        ;;
    [Nn]*)
        echo "Aborting..."
        exit 1
        ;;
    *) echo "Please enter y or n." ;;
    esac
}

function check_docker {
    if ! command -v docker &>/dev/null; then
        echo "Error: Docker is not installed or not found in WSL. Please install Docker Desktop and enable WSL integration."
        exit 1
    fi

    if ! docker info &>/dev/null; then
        echo "Error: Docker daemon is not running. Start Docker Desktop and ensure WSL integration is enabled."
        exit 1
    fi
}

function check_jq {
    if ! command -v jq &>/dev/null; then
        echo "jq is not installed. Installing jq..."
        sudo apt update && sudo apt install -y jq
    fi
}

function hostname_root {
    local domain="$1"

    IFS='.' read -r -a parts <<<"$domain"
    local n=${#parts[@]}

    if ((n <= 1)); then
        echo "$domain"
        return
    fi

    local known_sld=("co.uk" "gov.uk" "com.br" "co.jp")
    local tld_count=1
    local last_two="${parts[n - 2]}.${parts[n - 1]}"

    for sld in "${known_sld[@]}"; do
        if [[ "$last_two" == "$sld" ]]; then
            tld_count=2
            break
        fi
    done

    local main_idx=$((n - tld_count - 1))
    if ((main_idx < 0)); then
        main_idx=0
    fi

    echo "${parts[main_idx]}"
}

host_root_ssl_generate() {
    local FILENAME="${1:-rootCA}"
    local PASSPHRASE="${2:-default}"
    local VALIDITY_DAYS=29200  # 80 years
    local SUBJECT="/C=GB/ST=London/L=London/O=Lyntouch/OU=IT Department/CN=Lyntouch Self-Signed RootCA/emailAddress=info@lyntouch.com"

    # Calculate expiry date
    local EXPIRY_DATE
    EXPIRY_DATE=$(date -d "+$VALIDITY_DAYS days" "+%Y-%m-%d") || {
        echo "Error: Failed to calculate expiry date." >&2
        return 1
    }

    # Ensure CERTS_DIR is defined
    if [[ -z "$CERTS_DIR" ]]; then
        echo "Error: CERTS_DIR environment variable is not set." >&2
        return 1
    fi

    mkdir -p "$CERTS_DIR"

    local KEY_PATH="$CERTS_DIR/$FILENAME.key"
    local CRT_PATH="$CERTS_DIR/$FILENAME.crt"

    echo "Creating Root Certificate Authority:"
    echo "  Filename base:    $FILENAME"
    echo "  Key:              $KEY_PATH"
    echo "  Cert:             $CRT_PATH"
    echo "  Expires on:       $EXPIRY_DATE"
    echo "  Output directory: $CERTS_DIR"

    # Generate private key
    openssl genrsa -des3 -passout "pass:$PASSPHRASE" -out "$KEY_PATH" 4096 || return 1

    # Generate self-signed root certificate
    openssl req -x509 -new -nodes -passin "pass:$PASSPHRASE" \
        -key "$KEY_PATH" -sha256 -days "$VALIDITY_DAYS" \
        -subj "$SUBJECT" \
        -out "$CRT_PATH" || return 1

    echo "Root CA created successfully"
}

function add_host_ssl() {
    SSL_HOST=$1
    CRT_PATH="$CERTS_DIR/$SSL_HOST.crt"
    KEY_PATH="$CERTS_DIR/$SSL_HOST.key"
    CSR_PATH="$CERTS_DIR/$SSL_HOST.csr"
    EXT_FILE=$(add_host_ssl_extfile "$SSL_HOST")

    if [ ! -f "$KEY_PATH" ]; then
        print_color green "Generating SSL key for $SSL_HOST"
        openssl req -new -sha256 -nodes \
            -out "$CSR_PATH" -newkey rsa:2048 \
            -subj "/C=GB/ST=London/L=London/O=$SSL_HOST/OU=IT Department/CN=Lyntouch Self-Signed Host Certificate/emailAddress=info@lyntouch.com" \
            -keyout "$KEY_PATH"
    fi

    if [ ! -f "$CRT_PATH" ]; then
        print_color green "Generating SSL certificate for $SSL_HOST"
        openssl x509 -req -passin pass:default \
            -in "$CSR_PATH" \
            -CA "$ROOT_CRT" -CAkey "$ROOT_KEY" \
            -CAcreateserial -out "$CRT_PATH" \
            -days 500 -sha256 -extfile <(printf "$EXT_FILE")
    fi

    # rm -f "$CSR_PATH"
}

function add_host_ssl_extfile() {
    host_name=$1
    cat <<EOF
		authorityKeyIdentifier=keyid,issuer\n
		basicConstraints=CA:FALSE\n
		keyUsage=digitalSignature,nonRepudiation,keyEncipherment,dataEncipherment\n
		subjectAltName = @alt_names\n
		[alt_names]\n
		DNS.1 = $host_name
        IP.1 = 127.0.0.1
EOF
}

function add_host_redirect() {
    HOST="$1"
    if is_wsl; then
        WIN_HOSTS_FILE="/mnt/c/Windows/System32/drivers/etc/hosts"
        if grep -qP "^\s*127\.0\.0\.1.*$HOST(?:\s+|$)" "$WIN_HOSTS_FILE"; then
            return 0
        fi
        echo "Adding host redirection for \"$HOST\""
        powershell.exe -Command "New-HostnameMapping $HOST"
    else
        exists=$(getent hosts "$HOST")
        if [ -z "$exists" ]; then
            echo "Adding host redirection for \"$HOST\""
            echo "127.0.0.1 $HOST" | sudo tee -a /etc/hosts >/dev/null
        fi
    fi
}

function host_redirect_del {
    HOST="$1"
    echo "Removing host redirection for \"$HOST\""
    if is_wsl; then
        powershell.exe -Command "Remove-HostnameMapping $HOST"
    else
        if grep -q "$HOST" /etc/hosts; then
            sudo sed -i.bak "/$HOST/d" /etc/hosts
        fi
    fi
}

function is_wsl() {
    grep -q WSL /proc/version
}

function new_host {
    check_docker
    check_jq

    if [ -z "$HOST" ]; then
        echo "Usage: web new-host <hostname> [-t wp|laravel]"
        return 1
    fi

    case "$TYPE" in
    wp)
        new_wp "$HOST"
        ;;
    laravel)
        generate_supervisor_conf $HOST
        new_laravel "$HOST"
        ;;
    *)
        echo "Invalid type. Use wp for WordPress or laravel for Laravel."
        return 1
        ;;
    esac

    add_host_config "$TYPE" "$HOST"
    add_host_redirect "$HOST"

    build_webconf
}

function new_wp {
    program_installed curl || return 1
    program_installed tar || return 1
    echo "Setting up WordPress..."

    if [ ! -f "$WEB_ROOT/wordpress.tar.gz" ]; then
        curl https://en-gb.wordpress.org/latest-en_GB.tar.gz -o "$WEB_ROOT/wordpress.tar.gz"
    fi

    project_path="$WEB_ROOT/$HOST"
    if [ ! -d "$project_path" ]; then
        mkdir -p "$project_path"
        mkdir -p ./tmp_dir
        print_color green "Extracting Wordpress"
        tar -xzf "$WEB_ROOT/wordpress.tar.gz" -C ./tmp_dir
        mv ./tmp_dir/wordpress/* "$project_path"
        rm -rf ./tmp_dir
    else
        print_color yellow "Wordpress $project_path already exists, remove before continue"
        return 1
    fi

    # Setup Wordpress Config
    host_name=$(hostname_root $HOST)
    username="root"
    password="secret"
    sample_conf=$project_path/wp-config-sample.php
    dest_conf=$project_path/wp-config.php

    [ ! -f $dest_conf ] && mv $sample_conf $dest_conf

    sed -i "s/username_here/$username/g;s/database_name_here/$username/g;s/password_here/$password/g;s/localhost/mariadb/g;" $dest_conf

}
generate_supervisor_conf() {
    host="$1"
    host_name=$(echo "$1" | tr '.' '_')
    output_dir="${2:-/etc/supervisor/conf.d}"
    log_dir="/tmp/supervisor-logs/$host"
    program_name="$host_name"

    sudo mkdir -p "$log_dir"

    sudo tee "$output_dir/$program_name.conf" >/dev/null <<EOF
[program:$program_name]
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

    echo "✅ Supervisor config generated at $output_dir/$program_name.conf"
}

function new_laravel {
    echo "Setting up Laravel for $host..."
    host_name=$(hostname_root $host)

    project_path="$WEB_ROOT/$HOST"
    echo $project_path
    if [ ! -d "$project_path" ]; then
        mkdir -p "$project_path"
        composer create-project --prefer-dist laravel/laravel "$project_path"
        # Additional Laravel-specific setup steps can be added here
        # For example:
        # cp "$project_path/.env.example" "$project_path/.env"
        # php "$project_path/artisan" key:generate
        # php "$project_path/artisan" storage:link
    else
        print_color yellow "Laravel project $host_name already exists"
        return 1
    fi
}

function parse_args() {
    TYPE="wp"
    while [[ $# -gt 0 ]]; do
        case $1 in
        -t)
            TYPE=$2
            shift 2
            ;;
        *)
            HOST=$1
            shift
            ;;
        esac
    done

    if [ -z "$HOST" ]; then
        echo "No HOST parameter specified"
        exit 1
    fi
}

function program_installed {
    if ! [ -x "$(command -v $1)" ]; then
        echo "Error: $1 is not installed." >&2
        return 1
    fi
}

function print_color() {
    declare -A colors=(
        ['red']='\033[31m'
        ['green']='\033[0;32m'
        ['yellow']='\033[0;33m'
    )
    echo -e "${colors[$1]}$2\033[0m"
}

function host_remove() {
    db_name=$(get_db_name $HOST)
    if [ ! -z $db_name ]; then
        db_cmd remove $HOST
    fi

    echo "Removing $WEB_ROOT/$HOST"
    rm -rf "$WEB_ROOT/$HOST"

    host_redirect_del "$HOST"

    host_config_del
    build_webconf
}

function host_config_del {
    program_installed jq || return 1

    json_file="$WEB_ROOT/dev/web-hosts.json"

    existing_host=$(jq -r --arg hn "$HOST" '.hosts[] | select(.name == $hn)' $json_file)
    if [ ! -z "$existing_host" ]; then
        jq --arg hn "$HOST" 'del(.hosts[] | select(.name == $hn))' $json_file >"temp.json" && mv "temp.json" $json_file
    fi
}

function get_db_name() {
    host_name="$1"
    jq -r --arg host "$host_name" '.hosts[] | select(.name == $host) | .db' $WEB_ROOT/dev/web-hosts.json
}

function db_cmd {
    action=$1
    host_name=$2

    # Check if the host exists in the json file get its db name
    db_name=$(jq -r --arg hn "$host_name" '.hosts[] | select(.name == $hn) | .db' $WEB_ROOT/dev/web-hosts.json)

    if [ -z "$db_name" ]; then
        echo "No DB name specified"
        exit 1
    fi

    if [ $action == "create" ]; then
        $DC exec mariadb mariadb -uroot -psecret -e "CREATE USER IF NOT EXISTS ${db_name}@'%' IDENTIFIED BY 'secret';"
        $DC exec mariadb mariadb -uroot -psecret -e "CREATE DATABASE IF NOT EXISTS ${db_name};"
        $DC exec mariadb mariadb -uroot -psecret -e "GRANT ALL PRIVILEGES ON ${db_name}.* TO ${db_name}@'%'"
    else
        echo "Removing - database: $db_name user: $db_name"
        $DC exec mariadb mariadb -uroot -psecret -e "DROP DATABASE IF EXISTS ${db_name};"
        $DC exec mariadb mariadb -uroot -psecret -e "DROP USER IF EXISTS ${db_name}@'%';"
    fi
}

function import_ROOT_KEY_to_chrome() {
    # if WSL exit
    if [ -n "$WSL_DISTRO_NAME" ]; then
        echo "This script is not supported on WSL"
        return 1
    fi

    cert_filename=$1
    cert_nickname=${2:-"Root CA"}

    if [ -z "$cert_filename" ] || [ -z "$cert_nickname" ]; then
        echo "Usage: import_ROOT_KEY_to_chrome <certificate_filename> <certificate_nickname>"
        return 1
    fi

    # Convert PEM to DER
    openssl x509 -outform der -in "$cert_filename" -out "${cert_filename}.der"

    cert_dir="$HOME/.pki/nssdb"
    if [ ! -d "$cert_dir" ]; then
        mkdir -p "$cert_dir"
        certutil -N -d "$cert_dir"
    fi

    certutil -d sql:$cert_dir -A -t "C,," -n "$cert_nickname" -i "${cert_filename}.der"
    echo "Certificate ${cert_filename}.der imported to Chrome with nickname $cert_nickname"
}

case "$CMD" in
bash)
    $DC exec app bash
    ;;
build)
    build_service $2 $3
    ;;
build-webconf)
    build_webconf
    ;;
debug)
    mode=$2
    if [ -z "$mode" ]; then
        echo "Usage: web dev <mode>"
        echo "Available modes: off, debug, profile"
        return 1
    fi
    sed -i "s/XDEBUG_MODE=.*/XDEBUG_MODE=$mode/" $SCRIPT_DIR/.env
    $DC up -d franken_php
    ;;
supervisor-conf)
    generate_supervisor_conf $2
    ;;
supervisor-restart)
    systemctl is-enabled --quiet supervisor || sudo systemctl enable --now supervisor
    sudo systemctl restart supervisor
    sudo supervisorctl restart all
    ;;
dir)
    echo $SCRIPT_DIR
    ;;
fish)
    $DC exec franken_php fish
    ;;
git-update)
    user=${2}
    theme=${3}
    plugin=${4:-lyntouch-modules}

    if [[ -z "$theme" ]]; then
        echo "Please specify a theme"
        return 1
    fi

    ssh "${user}@lyntouch.com" "git -C public_html/wp-content/plugins/${plugin} pull; git -C public_html/wp-content/themes/${theme} pull"
    ;;
hostssl)
    add_host_ssl $HOST
    ;;
import-rootca)
    import_ROOT_KEY_to_chrome $ROOT_CRT
    ;;
install)
    ln -sf $SCRIPT_DIR/web.sh $HOME/.local/bin/web
    ln -sf $SCRIPT_DIR/web.completions.fish $HOME/.config/fish/completions/web.fish
    ;;
log)
    $DC logs -f $2
    ;;
new-host)
    shift # remove the 'new-host' argument
    parse_args "$@"
    new_host
    ;;
ps)
    $DC ps $2
    ;;
remove-host)
    shift
    parse_args "$@"
    confirm_action "Are you sure you want to remove $HOST?"
    host_remove $HOST
    ;;
restart)
    if [ -z "$2" ]; then
        echo "Restarting all containers"
    else
        echo "Restarting container: $2"
    fi
    $DC restart $2
    ;;
rootssl)
    host_root_ssl_generate
    # import_ROOT_KEY_to_chrome $ROOT_CRT
    $DC restart franken_php
    ;;
redis-flush)
    $DC exec redis redis-cli flushall
    ;;
redis-monitor)
    $DC exec redis redis-cli monitor
    ;;
stop)
    $DC stop $2
    ;;
down)
    $DC down
    ;;
up)
    $DC up -d $2
    ;;
*)
    cat <<EOF
WEB: Shell Utility script for web development

Allowed options:
    - bash:
        Access the app service's bash using Docker Compose.
    - build {service} {?--no-cache}:
        Build the specified or all Docker Compose service(s).
    - build-webconf:
        Rebuilds the web server configuration.
    - debug {mode}:
        Enables Xdebug for the app service. Available modes: off, debug, profile
    - dir:
        Change directory to the script directory.
    - fish:
        Access the app service's fish shell using Docker Compose.
    - supervisor-conf {host}:
        Generate supervisor configuration for the specified host.
    - git-update {user} {theme} {?plugin}:
        Update the specified theme and plugin via git on lyntouch.com.
    - hostssl {host}:
        Generates an SSL certificate for the specified host.
    - import-rootca:
        Imports the root Certificate Authority to Chrome.
    - install:
        Link the web.sh script to your local binary directory for easier access.
    - log {service}:
        Show the logs of the specified or all Docker Compose service(s).
    - new-host {host}:
        Set up a new WordPress site for the given host.
    - ps {service}:
        List Docker Compose service(s) status.
    - remove-host {host}:
        Removes the specified host and all associated configurations.
    - restart {service}:
        Restart the specified or all Docker Compose service(s).
    - restart-supervisor:
        Restart the supervisor service
    - rootssl:
        Generates a root SSL certificate and imports it to Chrome. Then rebuilds the php service.
    - redis-monitor:
        Access the redis service's monitor using Docker Compose.
    - redis-flush:
        Flush the redis service's cache using Docker Compose.
    - stop {service}:
        Stop the specified or all Docker Compose service(s).
    - down:
        Stop and remove all Docker Compose service(s).
    - up {service}:
        Up the specified or all Docker Compose service(s).

Usage examples:
    web install                              # Link web.sh script to local binary directory
    cd ?$(web dir)                           # Change directory to the script directory
    web bash                                 # Access app service's bash using Docker Compose
    web fish                                 # Access app service's fish shell using Docker Compose
    web build-webconf                        # Rebuild the web server configuration
    web build                                # Rebuild all Docker images and recreate all containers
    web build --no-cache                     # Rebuild all without cache Docker images and recreate all containers
    web build app                            # Rebuild the app Docker image and recreate the app container
    web build app --no-cache                 # Rebuild the app without cache Docker image and recreate the app container
    web restart                              # Restart the web server and rebuild the web server configuration
    web ps                                   # List all Docker Compose services
    web ps app                               # List the app Docker Compose service
    web new-host <hostname> [-t wp|laravel]  # Set up a new WordPress site for example.com
    web remove-host example.com              # Remove the host example.com and all associated configurations
    web rootssl                              # Generate a root SSL certificate and import it to Chrome. Then rebuild the php service.
    web hostssl example.com                  # Generate an SSL certificate for the host example.com
    web import-rootca                        # Import the root Certificate Authority to Chrome
EOF
    ;;
esac

#!/bin/bash

# set -o errexit
set -o pipefail

CMD="${1:-false}"
HOST="${2:-false}"
DEST="${3:-false}"

WEB_ROOT=${WEB_ROOT:-$HOME/www}
SCRIPT_DIR=${SCRIPT_DIR:-$HOME/www/dev}
SITES_DIR=$SCRIPT_DIR/php/config/sites
DC="docker compose -f $SCRIPT_DIR/docker-compose.yml"

readonly CERTS_DIR=$SCRIPT_DIR/php/config/ssl
readonly ROOT_KEY=$CERTS_DIR/rootCA.key
readonly ROOT_CRT=$CERTS_DIR/rootCA.crt

function add_host() {
    local host_entry="$1"
    if ! grep -q "$host_entry" /etc/hosts; then
        echo "Adding $host_entry to /etc/hosts"
        echo "127.0.0.1 $host_entry" | sudo tee -a /etc/hosts >/dev/null
    else
        print_color yellow "Host $host_entry is already in /etc/hosts"
    fi
}


function add_host_config {
    host_type="${1:-wordpress}"
    root_domain=$(echo "$HOST" | awk -F'.' '{print $(NF-1)"."$NF}')  # e.g., woodlandflooring.co.uk
    main_domain=$(echo "$root_domain" | cut -d'.' -f1)  # woodlandflooring
    sub_domain=$(echo "$HOST" | sed "s/\.$root_domain//")  # Removes root domain part

    if [[ "$sub_domain" != "$main_domain" ]]; then
        db_name="${main_domain}_$(echo $sub_domain | tr '.' '_')"
    else
        db_name="${main_domain}"
    fi

    if [ "$host_type" == "wordpress" ]; then
        db_name="${db_name}_wp"
    else
        db_name="${db_name}_db"
    fi

    db_name=$(echo "$db_name" | tr '.' '_')

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


function add_host_redirection {
    exists=$(getent hosts $1)
    if [ -z "$exists" ]; then
        echo "Adding localhost redirection for \"$1\""
        echo "127.0.0.1 $1" | sudo tee -a /etc/hosts >/dev/null
    else
        echo "Host \"$1\" already exists"
    fi
}

function build_webconf {
    config_path=$SCRIPT_DIR/web-hosts.json
    yaml_file="$SCRIPT_DIR/templates.yml"
    find $SCRIPT_DIR/php/config/sites -type f ! -name 'phpmyadmin.test.conf' ! -name '.gitkeep' -delete

    # Check if config file exists, if not create default one
    if [ ! -f $config_path ]; then
        echo "No config file found, creating default one"
        echo '{
            "output": "'$SITES_DIR'",
            "template": "'$SCRIPT_DIR'/php/config/template.conf",
            "WEB_ROOT": "'$WEB_ROOT'",
            "hosts": []
        }' >$config_path
        exit 1
    fi

    add_host "phpmyadmin.test"
    gen_host_ssl "phpmyadmin.test"

    echo "services:" >$yaml_file
    echo "  php:" >>$yaml_file
    echo "    networks:" >>$yaml_file
    echo "      dev_network:" >>$yaml_file
    echo "        aliases:" >>$yaml_file

    jq -c '.hosts[]' $config_path | while read i; do
        hostname=$(echo "$i" | jq -r '.name')
        echo "          - $hostname" >>$yaml_file
    done

    echo "" >$SCRIPT_DIR/crontab
    # Loop through each host in the config file
    jq -c '.hosts[]' $config_path | while read i; do
        hostname=$(echo "$i" | jq -r '.name')
        type=$(echo "$i" | jq -r '.type')
        DB=$(echo "$i" | jq -r '.db')

        # Ensure no leading `db_` prefix
        DB=$(echo "$DB" | sed -E 's/^db_//')

        # Ensure no invalid characters in the database name
        DB=$(echo "$DB" | tr '.' '_')

        serve_root="/var/www/$hostname"
        site_conf="$SITES_DIR/$hostname.conf"
        debugout="$HOME/www/$hostname/.vscode"

        echo "* * * * * cd /var/www/$hostname && php /var/www/$hostname/wp-cron.php >/proc/self/fd/1 2>/proc/self/fd/2" >>$SCRIPT_DIR/crontab

        add_host "$hostname"
        gen_host_ssl "$hostname"

        [ "$type" == "laravel" ] && serve_root="$serve_root/public"

        mkdir -p $debugout
        sed -e "s|\${HOSTNAME}|$hostname|g;" $SCRIPT_DIR/launch.json >$debugout/launch.json

        sed -e "s|\${APP_URL}|${hostname}|g;" \
            -e "s|\${SERVE_ROOT}|${serve_root}|g;" \
            $SCRIPT_DIR/php/config/template.conf >$site_conf

        echo "CREATE DATABASE IF NOT EXISTS \`${DB}\`;" | docker exec -i dev-mariadb-1 /usr/bin/mariadb -u root --password=secret

    done

    echo "Finished Building Web Configs Restarting Caddy"
    $DC restart php
}

function build_service {
    local service=""
    local flag=""

    for arg in "$@"; do
        if [[ $arg == "--no-cache" ]]; then
            flag="--no-cache"
        else
            service="$arg"
        fi
    done

    if [ -z "$service" ]; then
        $DC build $flag --parallel
        $DC up -d --force-recreate
    else
        $DC build $flag $service
        $DC up --force-recreate -d $service
    fi
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

function gen_root_ssl() {
    echo "Creating Root Certificate of Authority ..."
    FILENAME="${1:-rootCA}"
    KEY_PATH="$CERTS_DIR/$FILENAME.key"
    CRT_PATH="$CERTS_DIR/$FILENAME.crt"
    openssl genrsa -des3 -passout pass:default -out "$KEY_PATH" 4096
    openssl req -x509 -new -nodes -passin pass:default \
        -key "$KEY_PATH" -sha256 -days 20480 \
        -subj "/C=GB/ST=London/L=London/O=Lyntouch/OU=IT Department/CN=Lyntouch Self-Signed RootCA/emailAddress=info@lyntouch.com" \
        -out "$CRT_PATH"
}

function gen_host_ssl() {
    SSL_HOST=$1
    CRT_PATH="$CERTS_DIR/$SSL_HOST.crt"
    KEY_PATH="$CERTS_DIR/$SSL_HOST.key"
    CSR_PATH="$CERTS_DIR/$SSL_HOST.csr"
    EXT_FILE=$(gen_host_ssl_extfile "$SSL_HOST")

    if [ -f "$KEY_PATH" ]; then
        print_color yellow "SSL key for $SSL_HOST already exists at $KEY_PATH."
    else
        print_color green "Generating SSL key for $SSL_HOST"
        openssl req -new -sha256 -nodes \
            -out "$CSR_PATH" -newkey rsa:2048 \
            -subj "/C=GB/ST=London/L=London/O=$SSL_HOST/OU=IT Department/CN=Lyntouch Self-Signed Host Certificate/emailAddress=info@lyntouch.com" \
            -keyout "$KEY_PATH"
    fi

    if [ -f "$CRT_PATH" ]; then
        print_color yellow "SSL Certificate for $SSL_HOST already exists at $CRT_PATH."
    else
        print_color green "Generating SSL certificate for $SSL_HOST"
        openssl x509 -req -passin pass:default \
            -in "$CSR_PATH" \
            -CA "$ROOT_CRT" -CAkey "$ROOT_KEY" \
            -CAcreateserial -out "$CRT_PATH" \
            -days 500 -sha256 -extfile <(printf "$EXT_FILE")
    fi

    # [ -f "$CSR_PATH" ] && rm -f "$CSR_PATH"
}

function gen_host_ssl_extfile() {
    domain=$1
    cat <<EOF
		authorityKeyIdentifier=keyid,issuer\n
		basicConstraints=CA:FALSE\n
		keyUsage=digitalSignature,nonRepudiation,keyEncipherment,dataEncipherment\n
		subjectAltName = @alt_names\n
		[alt_names]\n
		DNS.1 = $domain
        IP.1 = 127.0.0.1
EOF
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
        new_laravel "$HOST"
        ;;
    *)
        echo "Invalid type. Use wp for WordPress or laravel for Laravel."
        return 1
        ;;
    esac

    add_host_config "$TYPE" "$HOST"
    if is_wsl; then
        powershell.exe -Command "New-HostnameMapping $HOST"
    else
        add_host_redirection "$HOST"
    fi
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
    root=$(root_domain $HOST)
    username=$root"_wp"
    password="secret"
    sample_conf=$project_path/wp-config-sample.php
    dest_conf=$project_path/wp-config.php

    [ ! -f $dest_conf ] && mv $sample_conf $dest_conf
    echo $username
    echo $password

    sed -i "s/username_here/$username/g;s/database_name_here/$username/g;s/password_here/$password/g;s/localhost/mariadb/g;" $dest_conf

    # # Setup Database
    db_cmd create wordpress
}

function new_laravel {
    local HOST=$1
    echo "Setting up Laravel for $HOST..."

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
        print_color yellow "Laravel project $project_path already exists, remove before continuing"
        return 1
    fi

    # # Setup Database
    # db_cmd create laravel
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

function root_domain {
    echo $1 | grep -oP '(.*?(?=\.\w{2,10}(\.\w{2,10})?$))'
}

function remove_host_config {
    program_installed jq || return 1

    json_file="$WEB_ROOT/dev/web-hosts.json"

    # Check if the host exists in the json file
    existing_host=$(jq -r --arg hn "$HOST" '.hosts[] | select(.name == $hn)' $json_file)
    if [ -z "$existing_host" ]; then
        echo "Error: Host $HOST does not exist in the JSON file." >&2
        exit 1
    fi

    # Remove the host from the json file
    jq --arg hn "$HOST" 'del(.hosts[] | select(.name == $hn))' $json_file >"temp.json" && mv "temp.json" $json_file
}

function remove_host_redirection {
    if grep -q $1 /etc/hosts; then
        sudo sed -i.bak "/$1/d" /etc/hosts
        echo "Host redirection for \"$1\" removed"
    else
        echo "Host redirection for \"$1\" does not exist"
    fi
}

function db_cmd {
    action=$1
    host_type=$2

    domain=$(root_domain $HOST)

    if [ "$host_type" == "wordpress" ]; then
        db_name="${domain}_wp"
    else
        db_name="${domain}_db"
    fi

    if [ -z "$db_name" ]; then
        echo "No DB name specified"
        exit 1
    fi

    if [ $action == "create" ]; then
        echo "Creating DB: $db_name"
        $DC exec mariadb mariadb -uroot -psecret -e "CREATE USER IF NOT EXISTS ${db_name}@'%' IDENTIFIED BY 'secret';"
        $DC exec mariadb mariadb -uroot -psecret -e "CREATE DATABASE IF NOT EXISTS ${db_name};"
        $DC exec mariadb mariadb -uroot -psecret -e "GRANT ALL PRIVILEGES ON ${db_name}.* TO ${db_name}@'%'"
    else
        echo "Removing $db_name user and database"
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
    $DC up -d php
    ;;
dir)
    echo $SCRIPT_DIR
    ;;
fish)
    $DC exec php fish
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
    gen_host_ssl $HOST
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
    confirm_action "Are you sure you want to remove $HOST?"
    remove_host_config $HOST
    db_cmd remove wordpress
    echo "Removing $WEB_ROOT/$HOST"
    rm -rf $WEB_ROOT/$HOST

    if is_wsl; then
        echo "removing wsl hosts redirection \n"
        echo "Remove-HostnameMapping $HOST"
        powershell.exe -Command "Remove-HostnameMapping $HOST"
    else
        remove_host_redirection $HOST
    fi

    build_webconf
    ;;
restart)
    $DC restart $2
    ;;
rootssl)
    gen_root_ssl
    import_ROOT_KEY_to_chrome $ROOT_CRT
    $DC restart php
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

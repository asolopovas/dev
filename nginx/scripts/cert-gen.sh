#!/bin/bash

ROOT_CA="/etc/letsencrypt/live/rootCA.key"
ROOT_CRT="/etc/letsencrypt/live/rootCA.crt"
HOST="${1:-false}"
CERTS_DIR=${2:-false}

if [ -z $HOST ] || [ -z $CERTS_DIR ]; then
    echo "Host and Certs Directory arguments required"
    exit 1
fi

function gen_host_ssl_extfile() {
    domain=$1
    cat <<EOF
		authorityKeyIdentifier=keyid,issuer\n
		basicConstraints=CA:FALSE\n
		keyUsage=digitalSignature,nonRepudiation,keyEncipherment,dataEncipherment\n
		subjectAltName = @alt_names\n
		[alt_names]\n
		DNS.1 = $domain
EOF
}

function gen_host_ssl() {
    if [ -z $HOST ]; then
        echo "Host argument is required"
        exit 1
    fi
    extFile=$(gen_host_ssl_extfile $HOST)
    openssl req -new -sha256 -nodes -out "$CERTS_DIR/$HOST.csr" -newkey rsa:2048 -subj "/C=GB/ST=London/L=London/O=$HOST/OU=IT Department/CN=$HOST Self Signed Certificate/emailAddress=info@$HOST" -keyout "$CERTS_DIR/privkey.pem"
    openssl x509 -req -passin pass:default -in "$CERTS_DIR/$HOST.csr" -CA "$ROOT_CRT" -CAkey "$ROOT_CA" -CAcreateserial -out "$CERTS_DIR/fullchain.pem" -days 500 -sha256 -extfile <(printf "$extFile")
    rm -f "$CERTS_DIR/$HOST.csr"
}

gen_host_ssl $HOST

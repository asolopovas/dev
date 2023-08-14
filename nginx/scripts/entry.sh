#!/bin/sh

# Start crond in background
crond -l 2 -b
cd /etc/letsencrypt/live

if [ ! -d /etc/nginx/sites-available ]; then
    mkdir /etc/nginx/sites-available
fi

if [ ! -d /etc/nginx/modules-enabled ]; then
    mkdir /etc/nginx/modules-enabled
fi

if [ ! -d /etc/nginx/sites-enabled ]; then
    mkdir /etc/nginx/sites-enabled
fi

function gencert {
    location=/etc/letsencrypt/live/$1/
    if echo $1 | grep -Eq "\.test$"; then
        if [ ! -d $location ] || [ ! -f $location/fullchain.pem ]; then
            mkdir -p $location
            cert-gen.sh $1 $location
        fi
    fi
}

SITES="/etc/nginx/sites-available/*"
for site in $SITES
do
  SITE=$(basename $site)
  SITE=${SITE//.conf/}
  gencert $SITE
done

rm -rf /etc/nginx/sites-enabled/*
find /etc/nginx/sites-available -type f -exec ln -sf {} /etc/nginx/sites-enabled/ \;

exec "$@"

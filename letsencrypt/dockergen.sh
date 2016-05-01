#!/bin/bash -e

# Is Let's encrypt feature enabled?
if [[ -z "${LETSENCRYPT_EMAIL}" ]]; then
  exit 0
fi

mkdir -p /ssl/letsencrypt

# We have to remove the last comma to make it a valid JSON.
LIST_JSON="$(cat /ssl/webroot/list.json | sed -n 'x;${s/,$//;p;x}; 2,$ p')"
# List of hosts in the JSON file.
HOSTS="$(echo "${LIST_JSON}" | jq --raw-output 'keys | .[]')"

for host in $HOSTS; do
  mkdir -p "/ssl/webroot/${host}"
done

# TODO: Remove "--test-cert" which is currently using for testing.
/letsencrypt/letsencrypt-auto --no-self-upgrade --noninteractive --agree-tos --email "${LETSENCRYPT_EMAIL}" \
 --config-dir /ssl/letsencrypt certonly --webroot --test-cert --keep-until-expiring --rsa-key-size 4096 \
 --webroot-map "${LIST_JSON}"

for host in $HOSTS; do
  if [ ! -e "letsencrypt/live/${host}/privkey.pem" ]; then
    echo "File 'letsencrypt/live/${host}/privkey.pem' is missing."
    exit 1
  fi
  if [ ! -e "letsencrypt/live/${host}/fullchain.pem" ]; then
    echo "File 'letsencrypt/live/${host}/fullchain.pem' is missing."
    exit 1
  fi

  ln -f -s "letsencrypt/live/${host}/privkey.pem" "/ssl/${host}.key"
  ln -f -s "letsencrypt/live/${host}/fullchain.pem" "/ssl/${host}.crt"
done

EXISTING_HOSTS="$(find /ssl -maxdepth 1 -lname 'letsencrypt*' -printf '%f\n' | rev | cut --fields=2- --delimiter '.' | rev | sort --unique)"

for host in $EXISTING_HOSTS; do
  if ! echo "${HOSTS}" | grep --quiet --line-regexp --fixed-strings "$host"; then
    rm -f "/ssl/${host}.key" "/ssl/${host}.crt"
  fi
done

# We can trigger dockergen rerun always because it does not call us back if list.json
# does not change, so an infinite loop does not happen.
sv hup dockergen

# We reload nginx always because content of files where links are pointing might changed.
/usr/sbin/nginx -s reload
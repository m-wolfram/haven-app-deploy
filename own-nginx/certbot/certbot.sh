#!/bin/sh
# Container certbot: the first Let's Encrypt certificate for HAVEN_DOMAIN in place of the temporary
# one from cert-init, then renewal. The domain check goes through nginx (port 80, webroot), nginx
# picks up a new certificate itself (see command of nginx in docker-compose.own-nginx.yml)
set -eu
trap exit TERM

live=/etc/letsencrypt/live/$HAVEN_DOMAIN
selfsigned=/etc/letsencrypt/selfsigned-$HAVEN_DOMAIN

if [ -n "${LETSENCRYPT_EMAIL:-}" ]; then
  email="--email $LETSENCRYPT_EMAIL"
else
  email=--register-unsafely-without-email
fi

# Wait until nginx accepts connections on 80: without it the domain check fails
python3 -c '
import socket, sys, time
for _ in range(60):
    try:
        socket.create_connection(("nginx", 80), 2).close()
        sys.exit(0)
    except OSError:
        time.sleep(1)
sys.exit("nginx does not answer on port 80")
'

# No renewal settings: live holds the temporary certificate from cert-init
while [ ! -f "/etc/letsencrypt/renewal/$HAVEN_DOMAIN.conf" ]; do
  # The previous run was stopped in the middle of an attempt: put the temporary one back
  if [ ! -d "$live" ] && [ -d "$selfsigned" ]; then
    mv "$selfsigned" "$live"
  fi
  # certbot does not write into a live directory it did not create: move the temporary one away,
  # put it back on failure
  rm -rf "$selfsigned"
  mv "$live" "$selfsigned"
  # shellcheck disable=SC2086 # $email is a flag with a value
  if certbot certonly --webroot -w /var/www/certbot -d "$HAVEN_DOMAIN" --cert-name "$HAVEN_DOMAIN" \
      $email --agree-tos --no-eff-email --non-interactive; then
    rm -rf "$selfsigned"
    echo "Got a Let's Encrypt certificate for $HAVEN_DOMAIN"
  else
    rm -rf "$live"
    mv "$selfsigned" "$live"
    echo "Failed to get a certificate for $HAVEN_DOMAIN (DNS points to this server? port 80 open?), retry in an hour" >&2
    sleep 1h & wait $!
  fi
done

while :; do
  certbot renew --webroot -w /var/www/certbot --quiet || echo "certbot renew failed, see above" >&2
  sleep 12h & wait $!
done

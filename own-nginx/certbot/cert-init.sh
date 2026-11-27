#!/bin/sh
# Container cert-init: if there is no certificate for HAVEN_DOMAIN yet, puts a temporary
# self-signed one so nginx can start. certbot (certbot.sh) then gets the Let's Encrypt one.
# Safe to run again
set -eu

live=/etc/letsencrypt/live/$HAVEN_DOMAIN

if [ -f "$live/fullchain.pem" ]; then
  echo "Certificate for $HAVEN_DOMAIN exists"
  exit 0
fi

mkdir -p "$live"
openssl req -x509 -nodes -newkey rsa:2048 -days 365 -subj "/CN=$HAVEN_DOMAIN" \
  -addext "subjectAltName=DNS:$HAVEN_DOMAIN" \
  -keyout "$live/privkey.pem" -out "$live/fullchain.pem" 2>/dev/null
echo "Created a temporary self-signed certificate for $HAVEN_DOMAIN"

# Haven deployment

This repository provides Docker Compose configurations for running [Haven](https://github.com/ancsemi/Haven) with the official `ghcr.io/ancsemi/haven` image. It supports local access, a bundled nginx with Let's Encrypt, or an existing nginx reverse proxy. An optional coturn service relays calls between clients on different networks.

## Quick start

With Docker and Docker Compose installed, run the following from the repository directory.

```bash
cp .env.example .env
docker compose up -d haven
```

Open `https://localhost:3000`. The local endpoint uses a self-signed certificate and is bound to `127.0.0.1`. The port can be changed with `HAVEN_PORT`.

For access over a domain, use [Bundled nginx](#bundled-nginx) if ports 80 and 443 are free, or [External nginx](#external-nginx) if an existing proxy already serves those ports. In `COMPOSE_FILE`, separate file names with a colon on Linux and macOS or a semicolon on Windows.

## Initial account setup

Registration is open on a fresh installation. The first account registered as `admin` receives administrator permissions. For either nginx mode, create this account before exposing Haven publicly. Start only the `haven` service on the server, then open an SSH tunnel from the local computer.

```bash
ssh -N -L 3000:127.0.0.1:3000 user@SERVER_IP
```

Behind nginx, Haven serves HTTP internally. Open `http://localhost:3000` through the tunnel. If `HAVEN_PORT` was changed, use that value as the destination port in the SSH command.

Under **Settings → Sign-ups**, enable **Require invite token** to restrict registration. Registration remains closed until an invite token is created. Use **Invite Code** to share an invitation.

## Bundled nginx

This mode requires TCP ports 80 and 443 to be available on the server. Copy the following settings into `.env` and replace the example hostname. `LETSENCRYPT_EMAIL` is optional.

```dotenv
COMPOSE_FILE=docker-compose.yml:docker-compose.own-nginx.yml
HAVEN_DOMAIN=chat.example.com
```

1. Point an `A` record at the server's public IPv4 address. Allow inbound TCP traffic on ports 80 and 443.
2. Start only Haven with `docker compose up -d haven` and [create the administrator account](#initial-account-setup).
3. Start the full stack and check the certificate issuance log.

```bash
docker compose up -d
docker compose logs --tail=50 certbot
```

nginx renders the site configuration from the [template](nginx/haven.conf.template) at startup. `cert-init` creates a temporary certificate. Certbot then obtains and renews the Let's Encrypt certificate, and nginx automatically reloads it.

## External nginx

Use this mode when an existing Docker-based nginx serves ports 80 and 443. Set up DNS and issue the certificate first. The generated configuration expects the certificate in `/etc/letsencrypt/live/<domain>/`.

Copy the following settings into `.env`. Replace the example hostname and network name. The network must already exist and be shared with nginx.

```dotenv
COMPOSE_FILE=docker-compose.yml:docker-compose.external-nginx.yml
HAVEN_DOMAIN=chat.example.com
PROXY_NETWORK=reverse-proxy
```

1. Start Haven with `docker compose up -d haven` and [create the administrator account](#initial-account-setup).
2. Render the nginx configuration.

   ```bash
   docker compose run --rm -T nginx-config > nginx/haven.conf.tmp &&
     mv nginx/haven.conf.tmp nginx/haven.conf
   ```

3. Mount the `nginx/` directory into the external nginx and include `haven.conf`. A directory mount lets nginx see the new file when it is regenerated. The proxy uses Docker DNS (`resolver 127.0.0.11`) to reach `haven:3000`.
4. From the external proxy's Compose project, test and reload the configuration. This example assumes the service is named `nginx`.

   ```bash
   docker compose exec nginx nginx -t &&
     docker compose exec nginx nginx -s reload
   ```

In both modes, nginx terminates TLS and passes the client IP to Haven in `X-Forwarded-For`. Haven trusts Docker network addresses by default and uses the client IP to rate-limit sign-in attempts.

When changing domains with an external proxy, obtain a certificate for the new hostname first. Update `HAVEN_DOMAIN`, regenerate the configuration, recreate the `haven` service, then reload nginx after `nginx -t` succeeds.

## Voice calls with TURN

coturn relays voice and screen sharing when clients cannot connect directly. To enable it, add `docker-compose.turn.yml` to either nginx configuration. For example:

```dotenv
COMPOSE_FILE=docker-compose.yml:docker-compose.external-nginx.yml:docker-compose.turn.yml
```

- `TURN_IP` is the public IPv4 address assigned to the Linux host's network interface. Deployments behind NAT also require `--external-ip`.
- `TURN_SECRET` is shared by Haven and coturn. Generate a random value with `openssl rand -hex 32`. Haven issues signed credentials valid for 24 hours.
- `TURN_MIN_PORT` and `TURN_MAX_PORT` set the UDP relay port range. The default range is `49160–49200`.

Allow inbound traffic on `3478/tcp`, `3478/udp`, and the selected UDP relay ports. The relay connects only to public addresses. It uses `turn:` without TLS.

```bash
docker compose up -d
docker compose logs --tail=50 coturn
```

Leave the TURN field under **Settings → Voice & Connectivity** blank so Haven uses the settings from `.env`. Use **Test voice connectivity** and place a call between devices on different networks to verify the setup.

## Updates

Create a [backup](#backup) before updating. The Haven version is pinned in `docker-compose.yml`. Set the image tag to the desired version from the [Haven releases](https://github.com/ancsemi/Haven/releases), then run:

```bash
docker compose pull haven &&
  docker compose up -d haven
```

After a template change, recreate the bundled nginx with `docker compose up -d --force-recreate nginx`. With an external nginx, regenerate the configuration, check it with `nginx -t`, and reload nginx.

When upgrading from a version that tracked `nginx/haven.conf` in Git, save a copy of the active configuration outside the nginx directory. Generate the new file after updating the repository and before reloading the external proxy.

## Backup

The `haven_data` Docker volume contains the `haven.db` database, uploaded files, and the `JWT_SECRET`. Stop Haven while creating the archive to get a consistent backup. The archive is written to a separate directory outside the repository.

```bash
backup_dir=$(mktemp -d)
if [ -n "$backup_dir" ] && docker compose stop haven; then
  if docker run --rm -v haven_haven_data:/data:ro -v "$backup_dir":/backup \
    alpine tar czf /backup/haven-data.tgz -C /data .; then
    echo "Backup: $backup_dir/haven-data.tgz"
  fi
  docker compose start haven
fi
```

`haven_haven_data` is the volume name for the default Compose project, `haven`. If the project has a different name, use its actual volume name.

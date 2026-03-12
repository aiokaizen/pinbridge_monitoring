# PinBridge Monitoring Server

This directory contains the self-hosted monitoring stack for PinBridge.

- [docker-compose.yml](/home/mouadk/workspace/pinbridge/monitoring/docker-compose.yml) builds the OpenStatus stack.
- [nginx.monitoring.conf.example](/home/mouadk/workspace/pinbridge/monitoring/nginx.monitoring.conf.example) is the host-level `nginx` reverse proxy template.
- [.env.example](/home/mouadk/workspace/pinbridge/monitoring/.env.example) is the configuration template.
- [monitoring.md](/home/mouadk/workspace/pinbridge/monitoring/monitoring.md) contains the monitoring design notes and monitor strategy.

## What This Stack Runs

The compose stack starts:

- `libsql`
- `tinybird-local`
- `workflows`
- `server`
- `private-location`
- `dashboard`
- `status-page`

Only these ports are bound on the host:

- `127.0.0.1:3002` for the OpenStatus operator dashboard
- `127.0.0.1:3003` for the public status page

`nginx` on the host terminates TLS and proxies the two public domains to those loopback ports.

## Prerequisites

The monitoring server must have:

1. Docker Engine installed.
2. Docker Compose v2 available as `docker compose`.
3. `nginx` installed systemwide.
4. Public DNS records pointing to this server:
   - `openstatus.yourdomain.com`
   - `status.yourdomain.com`
5. Outbound network access so Docker can build from `https://github.com/openstatusHQ/openstatus.git`.

## Step 1: Copy The Monitoring Folder To The Server

On the server, place this directory somewhere stable. Example:

```bash
sudo mkdir -p /opt/pinbridge
sudo chown "$USER":"$USER" /opt/pinbridge
cd /opt/pinbridge
git clone <your-pinbridge-repo-url> .
cd monitoring
```

If the repo is already on the server, just go into the folder:

```bash
cd /path/to/pinbridge/monitoring
```

## Step 2: Create The Environment File

Copy the example file:

```bash
cp .env.example .env
```

Edit `.env` and set these values at minimum:

- `MONITORING_DASHBOARD_DOMAIN`
- `MONITORING_STATUS_DOMAIN`
- `DASHBOARD_PUBLIC_URL`
- `STATUS_PAGE_PUBLIC_URL`
- `AUTH_SECRET`
- `CRON_SECRET`
- `SUPER_ADMIN_TOKEN`
- `RESEND_API_KEY`
- `OPENSTATUS_GIT_REF`

Recommended first pass:

```env
MONITORING_DASHBOARD_DOMAIN=openstatus.example.com
MONITORING_STATUS_DOMAIN=status.example.com
DASHBOARD_PUBLIC_URL=https://openstatus.example.com
STATUS_PAGE_PUBLIC_URL=https://status.example.com
MONITORING_DASHBOARD_BIND_IP=127.0.0.1
MONITORING_DASHBOARD_BIND_PORT=3002
MONITORING_STATUS_BIND_IP=127.0.0.1
MONITORING_STATUS_BIND_PORT=3003
OPENSTATUS_GIT_REF=main
NODE_ENV=production
SELF_HOST=true
AUTH_SECRET=<long-random-secret>
CRON_SECRET=<long-random-secret>
SUPER_ADMIN_TOKEN=<long-random-secret>
RESEND_API_KEY=<your-resend-api-key>
OPENSTATUS_PRIVATE_LOCATION_KEY=replace-after-bootstrap
```

Generate strong secrets with:

```bash
openssl rand -hex 32
```

Do not leave placeholder values in production.

## Step 3: Start The Stack

From the `monitoring/` directory:

```bash
docker compose up -d --build
```

Check status:

```bash
docker compose ps
```

Check logs if something fails:

```bash
docker compose logs --tail 200
```

Expected host bindings:

- dashboard on `127.0.0.1:3002`
- status page on `127.0.0.1:3003`

Verify locally on the server:

```bash
curl -I http://127.0.0.1:3002
curl -I http://127.0.0.1:3003
```

## Step 4: Configure Nginx

Copy the example config and replace the example domains with your real ones:

```bash
sudo cp nginx.monitoring.conf.example /etc/nginx/sites-available/pinbridge-monitoring.conf
sudo nano /etc/nginx/sites-available/pinbridge-monitoring.conf
```

The final config should proxy:

- `openstatus.yourdomain.com` -> `http://127.0.0.1:3002`
- `status.yourdomain.com` -> `http://127.0.0.1:3003`

Enable the site:

```bash
sudo ln -s /etc/nginx/sites-available/pinbridge-monitoring.conf /etc/nginx/sites-enabled/pinbridge-monitoring.conf
sudo nginx -t
sudo systemctl reload nginx
```

If another site is already using the same server names, fix that before reloading `nginx`.

## Step 5: Configure TLS On Nginx

If this server already uses Certbot with `nginx`, issue certificates for both domains:

```bash
sudo certbot --nginx -d openstatus.yourdomain.com -d status.yourdomain.com
```

After Certbot updates the config, test and reload:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

Then verify:

```bash
curl -I https://openstatus.yourdomain.com
curl -I https://status.yourdomain.com
```

## Step 6: Bootstrap OpenStatus

Open the dashboard domain in the browser:

```text
https://openstatus.yourdomain.com
```

Complete the initial OpenStatus setup and sign in.

## Step 7: Create The Private Location Key

In OpenStatus:

1. Go to `Settings`.
2. Go to `Private Locations`.
3. Create a new private location.
4. Copy the generated key.

Put that key into `.env`:

```env
OPENSTATUS_PRIVATE_LOCATION_KEY=<real-private-location-key>
```

Restart only the private-location container:

```bash
docker compose up -d private-location
docker compose ps
```

If `private-location` still fails, inspect:

```bash
docker compose logs private-location --tail 200
```

## Step 8: Configure PinBridge Monitors

Create these monitors in OpenStatus first:

1. WebApp public availability
   - URL: `https://app.pinbridge.io/`
   - interval: `30s`
   - probe location: public

2. API liveness
   - URL: `https://api.pinbridge.io/healthz`
   - interval: `30s`
   - probe location: public

3. API readiness
   - URL: `https://api.pinbridge.io/readyz`
   - interval: `30s`
   - probe location: private location

Do not use `/statusz` as the primary uptime monitor.

## Step 9: Configure Internal `/statusz` Monitoring

`/statusz` is for internal monitoring only. If PinBridge protects it with bearer auth or source-IP allowlisting, configure that first on the PinBridge API side.

On the PinBridge API server:

1. Set `ADMIN_API_TOKEN` to a strong secret.
2. Set `ADMIN_ALLOWED_HOSTS` so the monitoring server IP is allowed.
3. Redeploy the API.

Then create a private monitor or internal automation against:

```text
https://api.pinbridge.io/statusz
```

If you require a bearer token, configure the monitor to send:

```text
Authorization: Bearer <ADMIN_API_TOKEN>
```

Use `/statusz` for:

- readiness failure diagnosis
- queue backlog alerts
- worker availability alerts
- provider configuration drift

Use a lower polling rate such as `60s` or `120s`.

## Step 10: Validate The Whole Setup

Check Docker services:

```bash
cd /path/to/pinbridge/monitoring
docker compose ps
```

Check nginx:

```bash
sudo nginx -t
systemctl status nginx --no-pager
```

Verify public endpoints:

```bash
curl -I https://openstatus.yourdomain.com
curl -I https://status.yourdomain.com
curl -s https://api.pinbridge.io/healthz
curl -s https://api.pinbridge.io/readyz
```

Verify internal status access if enabled:

```bash
curl -s -H 'Authorization: Bearer <ADMIN_API_TOKEN>' https://api.pinbridge.io/statusz
```

## Updating The Monitoring Stack

To update the running stack later:

```bash
cd /path/to/pinbridge/monitoring
docker compose up -d --build
```

If you want to pin OpenStatus to a specific tag or commit instead of `main`, change:

```env
OPENSTATUS_GIT_REF=<tag-or-commit>
```

That is safer than tracking `main` forever.

## Operational Notes

- The compose file builds OpenStatus directly from the upstream Git repo. That is simple, but it means the server needs outbound GitHub access during build.
- `dashboard` and `status-page` are intentionally bound to loopback only. Do not change them to `0.0.0.0` unless you want to bypass `nginx`.
- `private-location` will not become healthy until `OPENSTATUS_PRIVATE_LOCATION_KEY` is set correctly.
- `statusz` should not be exposed publicly without auth or network restrictions.

# PinBridge Monitoring Server

This directory contains the self-hosted monitoring stack for PinBridge.

- [docker-compose.yml](/home/mouadk/workspace/pinbridge/monitoring/docker-compose.yml) runs the monitoring stack.
- [conf/nginx.monitoring.conf.example](/home/mouadk/workspace/pinbridge/monitoring/conf/nginx.monitoring.conf.example) is the host-level `nginx` reverse proxy template.
- [.env.example](/home/mouadk/workspace/pinbridge/monitoring/.env.example) is the runtime configuration template.
- [monitoring.md](/home/mouadk/workspace/pinbridge/monitoring/monitoring.md) contains the monitoring design notes.
- [Makefile](/home/mouadk/workspace/pinbridge/monitoring/Makefile) contains the recurring recovery/admin commands for this stack.

## What This Stack Runs

The compose stack starts:

- `libsql`
- `redis`
- `redis-http`
- `tinybird-local`
- `workflows`
- `checker`
- `server`
- `private-location`
- `dashboard`
- `status-page`

Useful operator shortcut:

```bash
make help
```

Only these ports are bound on the host:

- `127.0.0.1:3002` for the OpenStatus operator dashboard
- `127.0.0.1:3003` for the public status page
- `127.0.0.1:3001` for the internal OpenStatus server callback surface

Everything else stays on the private Docker bridge network and is not published on the host.

This stack is intentionally self-host only:

- it builds from a local `openstatus/` checkout
- it does not require Google Cloud Tasks
- it does not use OpenStatus cloud checker endpoints
- it assumes one local checker region, configured by `CHECKER_REGION`

## Prerequisites

The monitoring server must have:

1. Docker Engine installed.
2. Docker Compose v2 available as `docker compose`.
3. `nginx` installed systemwide.
4. Public DNS records pointing to this server:
   - `openstatus.pinbridge.io`
   - `status.pinbridge.io`
5. Enough disk space to build OpenStatus images locally.

## Directory Layout On The Server

The monitoring stack builds from `../openstatus`, so the simplest server layout is:

```text
/opt/pinbridge/
  monitoring/
  openstatus/
```

If you keep `openstatus/` somewhere else, set `OPENSTATUS_SOURCE_DIR` in `.env` to the absolute path.

## Step 1: Copy Both Folders To The Server

On the server:

```bash
sudo mkdir -p /opt/pinbridge
sudo chown "$USER":"$USER" /opt/pinbridge
cd /opt/pinbridge
```

Copy these two directories from your workstation or repo checkout:

- `monitoring/`
- `openstatus/`

Example with `rsync` from your local machine:

```bash
rsync -av --delete /local/path/to/pinbridge/monitoring/ user@server:/opt/pinbridge/monitoring/
rsync -av --delete /local/path/to/pinbridge/openstatus/ user@server:/opt/pinbridge/openstatus/
```

If both directories already exist on the server, just continue.

## Step 2: Create `.env`

From the server:

```bash
cd /opt/pinbridge/monitoring
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
- `UPSTASH_REDIS_REST_TOKEN`
- `OPENSTATUS_SOURCE_DIR`

Recommended starting config:

```env
MONITORING_DASHBOARD_DOMAIN=openstatus.pinbridge.io
MONITORING_STATUS_DOMAIN=status.pinbridge.io
DASHBOARD_PUBLIC_URL=https://openstatus.pinbridge.io
STATUS_PAGE_PUBLIC_URL=https://status.pinbridge.io
MONITORING_DASHBOARD_BIND_IP=127.0.0.1
MONITORING_DASHBOARD_BIND_PORT=3002
MONITORING_STATUS_BIND_IP=127.0.0.1
MONITORING_STATUS_BIND_PORT=3003
MONITORING_SERVER_BIND_IP=127.0.0.1
MONITORING_SERVER_BIND_PORT=3001

OPENSTATUS_SOURCE_DIR=/opt/pinbridge/openstatus
OPENSTATUS_BUILD_TAG=pinbridge-selfhost

NODE_ENV=production
SELF_HOST=true
AUTH_SECRET=<long-random-secret>
CRON_SECRET=<long-random-secret>
SUPER_ADMIN_TOKEN=<long-random-secret>

CHECKER_BASE_URL=http://checker:8080
CHECKER_REGION=ams
WORKFLOWS_BASE_URL=http://workflows:3000
OPENSTATUS_WORKFLOWS_URL=http://workflows:3000
OPENSTATUS_INGEST_URL=http://server:3000

DATABASE_URL=http://libsql:8080
SQLD_DB_PATH=/var/lib/sqld/iku.db
UPSTASH_REDIS_REST_URL=http://redis-http:80
UPSTASH_REDIS_REST_TOKEN=<long-random-secret>
TINYBIRD_URL=http://tinybird-local:7181

RESEND_API_KEY=<your-resend-api-key>
OPENSTATUS_PRIVATE_LOCATION_KEY=replace-after-bootstrap
```

Generate strong secrets with:

```bash
openssl rand -hex 32
```

Do not leave placeholder values in production.
Do not keep unused optional variables in the real `.env` as blank assignments. Omit them entirely.
Do not change `SQLD_DB_PATH` after first boot unless you are intentionally migrating the libsql database file. If that path drifts, OpenStatus can come back against a fresh SQLite file and appear to "lose" monitors, pages, and workspace plan state even though the named volume still exists.

## Step 3: Build And Start The Stack

From the `monitoring/` directory:

```bash
docker compose up -d --build
```

Then inspect:

```bash
docker compose ps
docker compose logs workflows --tail 200
docker compose logs checker --tail 200
```

Expected healthy services:

- `pinbridge-monitoring-libsql`
- `pinbridge-monitoring-redis`
- `pinbridge-monitoring-redis-http`
- `pinbridge-monitoring-tinybird`
- `pinbridge-monitoring-workflows`
- `pinbridge-monitoring-checker`
- `pinbridge-monitoring-server`
- `pinbridge-monitoring-private-location`
- `pinbridge-monitoring-dashboard`
- `pinbridge-monitoring-status-page`

Persistence check after first boot:

```bash
docker volume inspect pinbridge-monitoring-libsql-data
docker run --rm -v pinbridge-monitoring-libsql-data:/data alpine sh -lc 'ls -lah /data'
```

You should see the libsql database file at the path configured by `SQLD_DB_PATH`, typically `/var/lib/sqld/iku.db`.

Local health checks on the server:

```bash
curl -I http://127.0.0.1:3002
curl -I http://127.0.0.1:3003
docker compose exec checker wget -qO- http://localhost:8080/health
docker compose exec workflows wget -qO- http://localhost:3000/ping
```

If you change OpenStatus source code later:

```bash
docker compose up -d --build --force-recreate
```

## Step 4: Configure `nginx`

Copy the example config:

```bash
sudo cp conf/nginx.monitoring.conf.example /etc/nginx/sites-available/pinbridge-monitoring.conf
sudo nano /etc/nginx/sites-available/pinbridge-monitoring.conf
```

The final config should proxy:

- `openstatus.pinbridge.io` -> `http://127.0.0.1:3002`
- `status.pinbridge.io` -> `http://127.0.0.1:3003`
- `openstatus.pinbridge.io/slack/*` -> `http://127.0.0.1:3001/slack/*`

Enable it:

```bash
sudo ln -s /etc/nginx/sites-available/pinbridge-monitoring.conf /etc/nginx/sites-enabled/pinbridge-monitoring.conf
sudo nginx -t
sudo systemctl reload nginx
```

If another site already owns the same domains, fix that first.

## Step 5: Configure TLS

If this server already uses Certbot with `nginx`:

```bash
sudo certbot --nginx -d openstatus.pinbridge.io -d status.pinbridge.io
sudo nginx -t
sudo systemctl reload nginx
```

Verify:

```bash
curl -I https://openstatus.pinbridge.io
curl -I https://status.pinbridge.io
```

## Step 6: Bootstrap OpenStatus

Open:

```text
https://openstatus.pinbridge.io
```

Sign in and complete initial setup.

## Step 7: Create The Private Location Key

In OpenStatus:

1. Go to `Settings`.
2. Go to `Private Locations`.
3. Create a private location.
4. Copy the generated key.

Put that key into `.env`:

```env
OPENSTATUS_PRIVATE_LOCATION_KEY=<real-private-location-key>
```

Restart only that service:

```bash
cd /opt/pinbridge/monitoring
docker compose up -d private-location
docker compose logs private-location --tail 100
```

## Step 8: Create PinBridge Monitors

Create these first:

1. WebApp public availability
   - URL: `https://app.pinbridge.io/`
   - interval: `1m`
   - location: public
   - region: `ams`

2. API liveness
   - URL: `https://api.pinbridge.io/healthz`
   - interval: `1m`
   - location: public
   - region: `ams`

3. API readiness
   - URL: `https://api.pinbridge.io/readyz`
   - interval: `1m`
   - location: private location
   - region: `ams`

4. Internal diagnostics
   - URL: `https://api.pinbridge.io/statusz`
   - interval: `60s` or `120s`
   - location: private location
   - region: `ams`
   - auth header if required

Do not use `/statusz` as the primary uptime probe.

## Step 9: Protect And Use `/statusz`

`/statusz` is for internal monitoring only.

On the PinBridge API side:

1. Set `ADMIN_API_TOKEN`.
2. Set `ADMIN_ALLOWED_HOSTS` to allow the monitoring server IP.
3. Redeploy the API.

If `/statusz` requires bearer auth, configure the monitor header as:

```text
Authorization: Bearer <ADMIN_API_TOKEN>
```

## Step 10: Validate The Whole Setup

Check containers:

```bash
cd /opt/pinbridge/monitoring
docker compose ps
```

Check nginx:

```bash
sudo nginx -t
systemctl status nginx --no-pager
```

Verify endpoints:

```bash
curl -I https://openstatus.pinbridge.io
curl -I https://status.pinbridge.io
curl -s https://api.pinbridge.io/healthz
curl -s https://api.pinbridge.io/readyz
curl -s -H 'Authorization: Bearer <ADMIN_API_TOKEN>' https://api.pinbridge.io/statusz
```

## Updating The Stack

When you change the local OpenStatus fork:

```bash
cd /opt/pinbridge/openstatus
git pull
cd /opt/pinbridge/monitoring
docker compose up -d --build --force-recreate
docker compose ps
```

## Operational Notes

- This self-host path is single-checker-region by design. Use the region from `CHECKER_REGION`, default `ams`.
- Use `1m` or slower monitor intervals. This self-host path does not emulate OpenStatus cloud's `30s` split scheduling.
- Do not track upstream `main` in production and hope it stays working. Build from your audited local checkout or your own fork.
- If the stack breaks, inspect `workflows`, `checker`, and `server` first. Those are the critical self-host pieces.

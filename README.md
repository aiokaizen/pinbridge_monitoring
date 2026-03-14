# PinBridge Monitoring Server

This directory now runs PinBridge monitoring with Uptime Kuma, not OpenStatus.

That is an intentional simplification:

- one container instead of a fragile multi-service stack
- one persistent volume
- no framework patching
- no custom migrations
- no cron scheduler glue
- no workspace or billing state to recover

- [docker-compose.yml](/home/mouadk/workspace/pinbridge/monitoring/docker-compose.yml) runs the Uptime Kuma stack.
- [conf/nginx.monitoring.conf.example](/home/mouadk/workspace/pinbridge/monitoring/conf/nginx.monitoring.conf.example) is the host-level `nginx` reverse proxy template.
- [.env.example](/home/mouadk/workspace/pinbridge/monitoring/.env.example) is the runtime configuration template.
- [monitoring.md](/home/mouadk/workspace/pinbridge/monitoring/monitoring.md) contains the monitoring design notes.
- [Makefile](/home/mouadk/workspace/pinbridge/monitoring/Makefile) contains the recurring operator commands for this stack.

Useful operator shortcut:

```bash
make help
```

## What This Stack Runs

The compose stack starts exactly one service:

- `kuma`

Only one port is bound on the host:

- `127.0.0.1:3002` for the Uptime Kuma web UI

`nginx` should expose that same Kuma instance on two public domains:

- `openstatus.pinbridge.io` for the operator dashboard
- `status.pinbridge.io` for the public status page

The status domain is just a dedicated reverse-proxy entry point to a Kuma status page slug such as `/status/pinbridge`.

## Prerequisites

The monitoring server must have:

1. Docker Engine installed.
2. Docker Compose v2 available as `docker compose`.
3. `nginx` installed systemwide.
4. Public DNS records pointing to this server:
   - `openstatus.pinbridge.io`
   - `status.pinbridge.io`

## Step 1: Copy `monitoring/` To The Server

On the server:

```bash
sudo mkdir -p /opt/pinbridge
sudo chown "$USER":"$USER" /opt/pinbridge
cd /opt/pinbridge
```

Copy this directory from your workstation or repo checkout:

- `monitoring/`

Example with `rsync` from your local machine:

```bash
rsync -av --delete /local/path/to/pinbridge/monitoring/ user@server:/opt/pinbridge/monitoring/
```

## Step 2: Create `.env`

From the server:

```bash
cd /opt/pinbridge/monitoring
cp .env.example .env
```

Edit `.env` and set these values:

- `MONITORING_DASHBOARD_DOMAIN`
- `MONITORING_STATUS_DOMAIN`
- `MONITORING_KUMA_BIND_IP`
- `MONITORING_KUMA_BIND_PORT`
- `KUMA_STATUS_PAGE_SLUG`
- `TZ`

Recommended starting config:

```env
MONITORING_DASHBOARD_DOMAIN=openstatus.pinbridge.io
MONITORING_STATUS_DOMAIN=status.pinbridge.io
MONITORING_KUMA_BIND_IP=127.0.0.1
MONITORING_KUMA_BIND_PORT=3002
KUMA_STATUS_PAGE_SLUG=pinbridge
UPTIME_KUMA_IMAGE=louislam/uptime-kuma:1
TZ=Africa/Casablanca
```

The `PINBRIDGE_*` monitor target values in [.env.example](/home/mouadk/workspace/pinbridge/monitoring/.env.example) are documentation inputs for the monitors you create in the Kuma UI. Kuma does not read them automatically.

## Step 3: Start The Stack

From the `monitoring/` directory:

```bash
make up
```

Then inspect:

```bash
make ps
make logs
curl -I http://127.0.0.1:3002
```

Persistence check:

```bash
make persistence-check
```

You should see Kuma data files inside the named volume `pinbridge-monitoring-kuma-data`.

## Step 4: Configure `nginx`

Copy the example config:

```bash
sudo cp conf/nginx.monitoring.conf.example /etc/nginx/sites-available/pinbridge-monitoring.conf
sudo nano /etc/nginx/sites-available/pinbridge-monitoring.conf
```

Update the example:

- replace `openstatus.example.com` with your dashboard domain
- replace `status.example.com` with your public status domain
- replace `/status/pinbridge` with `/status/<your-status-page-slug>` if you changed `KUMA_STATUS_PAGE_SLUG`

The final config should proxy:

- `openstatus.pinbridge.io` -> `http://127.0.0.1:3002`
- `status.pinbridge.io` -> `http://127.0.0.1:3002`
- `https://status.pinbridge.io/` -> redirect to `https://status.pinbridge.io/status/pinbridge`

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

## Step 6: First Boot In Uptime Kuma

Open:

- `https://openstatus.pinbridge.io`

On first boot:

1. Create the Kuma admin account.
2. Set notification channels in the UI.
3. Create the public status page with slug `pinbridge` or whatever you set in `.env`.
4. Attach the monitors you want exposed publicly.

There is no billing plan, no workspace recovery, no migrations, and no private-location bootstrap anymore. That entire OpenStatus failure surface is gone.

## Recommended Monitors

Start with these monitors:

1. Website
   - type: `HTTP(s)`
   - URL: `https://www.pinbridge.io/`
   - interval: `60s`

2. App
   - type: `HTTP(s)`
   - URL: `https://app.pinbridge.io/`
   - interval: `60s`

3. API Health
   - type: `HTTP(s)`
   - URL: `https://api.pinbridge.io/healthz`
   - interval: `60s`

4. API Ready
   - type: `HTTP(s)`
   - URL: `https://api.pinbridge.io/readyz`
   - interval: `60s`
   - only create this if the monitoring server is allowed to reach it

5. API Status
   - type: `HTTP(s)`
   - URL: `https://api.pinbridge.io/statusz`
   - interval: `120s`
   - add auth headers if needed
   - keep this internal if it exposes too much detail

For protected endpoints, use Kuma request headers instead of weakening the endpoint just for monitoring.

## Backup

Create a volume backup before major server changes:

```bash
make backup
```

That creates a tarball under `monitoring/backups/`.

## What Changed From OpenStatus

This repo no longer provides:

- OpenStatus builds
- libsql
- Redis
- Tinybird
- workflows
- checker
- private locations
- workspace SQL recovery commands
- monitor scheduler cron jobs

If you still have old OpenStatus data somewhere, this stack does not migrate it. Recreate the monitors and the Kuma status page manually.

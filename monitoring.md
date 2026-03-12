# Monitoring Notes

Deployment and server setup instructions live in [README.md](/home/mouadk/workspace/pinbridge/monitoring/README.md).

## Decisions

- Do not build a custom heartbeat service.
- Use the API's built-in health surfaces instead:
  - `/healthz` for cheap liveness
  - `/readyz` for strict readiness
  - `/statusz` for detailed runtime diagnostics
- Use a layered model:
  - public synthetic checks for user-facing availability
  - private synthetic checks for strict API readiness
  - structured status inspection for internal systems and provider configuration
  - queue/backlog alerting based on `statusz`
  - public incident/uptime reporting via OpenStatus
- For self-hosted uptime and status pages, use OpenStatus.
- Deploy OpenStatus with Docker Compose behind a host-level `nginx` reverse proxy.
- Keep OpenStatus internals private; only bind the dashboard and public status page to loopback and let `nginx` expose them over `80/443`.

## Endpoint Roles

### `GET /healthz`

Purpose:

- confirm the API process is alive
- stay cheap enough for high-frequency probes

What it checks:

- API process only

What it does **not** prove:

- database reachability
- Redis reachability
- Celery worker availability
- asset storage writability

Use it for:

- container liveness
- public uptime probes
- basic smoke checks

### `GET /readyz`

Purpose:

- decide whether this API instance should receive traffic

What it checks:

- database connectivity and migration table visibility
- Redis connectivity
- Celery broker connectivity
- Celery result backend connectivity
- asset storage directory writability
- at least one Celery worker responding to control ping

Behavior:

- returns `200` only when all required checks are healthy
- returns `503` when any required runtime dependency is not healthy

Use it for:

- reverse proxy / load balancer readiness
- internal uptime checks from a private probe location
- deployment smoke tests

### `GET /statusz`

Purpose:

- return a structured runtime snapshot for diagnosis and alert enrichment

What it includes:

- readiness summary
- internal system check results
- queue/backlog counts
- external provider configuration status

Use it for:

- operator diagnostics
- alert investigation
- low-frequency internal polling
- automation that needs structured health data

Do **not** use `statusz` as the high-frequency public uptime probe. It is more expensive than `healthz` and `readyz`.

## Monitoring Strategy

Monitor these components:

- WebApp
- API process
- API readiness
- Postgres
- Redis
- Celery workers
- queue backlog and stuck work
- host/container resources
- external provider configuration drift

Recommended intervals:

- public synthetic checks: every `30s`
- private readiness checks: every `30s`
- `statusz` polling: every `60s` to `120s`
- queue/backlog evaluation: every `60s`

Avoid probing everything every few seconds. `statusz` touches multiple subsystems and should not be your hot-path uptime check.

## Monitor Matrix

### Public checks

WebApp:

- URL: `https://app.pinbridge.io/`
- expectation: `200`
- purpose: user-facing availability

API liveness:

- URL: `https://api.pinbridge.io/healthz`
- expectation: `200` and JSON `status=ok`
- purpose: public API process availability

### Private checks

API readiness:

- URL: `https://api.pinbridge.io/readyz`
- run from: private OpenStatus location
- expectation: `200`
- failure means: do not trust the instance for real traffic

Detailed runtime snapshot:

- URL: `https://api.pinbridge.io/statusz`
- run from: private OpenStatus location or internal automation
- expectation: JSON with:
  - top-level `status`
  - `readiness.ready`
  - `internal_systems`
  - `queue_snapshot`
  - `external_providers`

Container health:

- continue using Docker/container health checks locally on the services themselves
- these are not a replacement for `readyz`

## What `statusz` Should Drive

Alert on these fields or derived conditions:

- `readiness.ready = false`
- `internal_systems.database.status != ok`
- `internal_systems.redis.status != ok`
- `internal_systems.celery_broker.status != ok`
- `internal_systems.celery_result_backend.status != ok`
- `internal_systems.asset_storage.status != ok`
- `internal_systems.celery_workers.status != ok`
- `queue_snapshot.overdue_schedules > 0` for sustained periods
- `queue_snapshot.queued_pins` growing without recovery
- `queue_snapshot.queued_import_jobs` growing without recovery
- `queue_snapshot.queued_emails` growing without recovery

Treat queue alerts as symptom alerts, not hard readiness gates. A backlog can mean saturation or a dead worker/scheduler path, but the API may still be up.

## External Provider Interpretation

`statusz` exposes provider information for:

- Pinterest
- Resend
- Stripe
- Sentry
- GA4

Important:

- this is configuration/status context, not a guarantee that each external API is live at that exact moment
- do not turn every provider into a blocking readiness dependency
- external providers can be monitored separately with targeted runbooks if needed

Use provider data from `statusz` to catch:

- missing production credentials
- disabled integrations that should be enabled
- configuration drift across environments

## OpenStatus Topology

Use two public domains:

- `openstatus.yourdomain.com` for the operator dashboard
- `status.yourdomain.com` for the public status page

Keep these internal only:

- `libsql`
- `tinybird-local`
- `server`
- `checker`
- `workflows`
- `private-location`

Publicly expose only:

- `80`
- `443`

## OpenStatus Probe Design

Create these monitors first:

1. WebApp public availability
   - target: `https://app.pinbridge.io/`
   - cadence: `30s`
   - probe type: public

2. API liveness
   - target: `https://api.pinbridge.io/healthz`
   - cadence: `30s`
   - probe type: public

3. API readiness
   - target: `https://api.pinbridge.io/readyz`
   - cadence: `30s`
   - probe type: private

Do not make `statusz` the primary OpenStatus uptime target. Use it as a secondary diagnostic endpoint and for internal automation.

## Alert Rules

Start with these alert rules:

1. WebApp public down
   - trigger: 3 consecutive failures
   - severity: high

2. API liveness down
   - trigger: 3 consecutive failures
   - severity: high

3. API readiness failing
   - trigger: 2 consecutive failures
   - severity: high

4. No Celery workers responding
   - source: `statusz`
   - trigger: 2 consecutive polls
   - severity: high

5. Overdue schedules present
   - source: `statusz`
   - trigger: sustained for `5m`
   - severity: medium

6. Queue backlog growth without recovery
   - source: `statusz`
   - trigger: sustained upward trend for `10m`
   - severity: medium

7. Missing required external provider configuration in production
   - source: `statusz`
   - trigger: first detection plus daily reminder until fixed
   - severity: medium

## Deployment Notes

Use prebuilt GHCR images rather than building OpenStatus from source on the server.

Minimum reasonable OpenStatus VPS:

- `2 vCPU`
- `4 GB RAM`
- `120 GB NVMe`

Rejected options:

- `1 vCPU / 1 GB / 10 GB NVMe`: too small
- `2 vCPU / 2 GB / 80 GB NVMe`: borderline, not preferred
- `4 vCPU / 8 GB / 75 GB SSD + swap`: worse storage profile than `2/4/120 NVMe`

## Environment and Secrets

OpenStatus still needs its own `.env.docker`, reverse proxy, database, and optional Tinybird setup. Keep the previous deployment mechanics, but the monitor definitions should now explicitly target PinBridge endpoints with the roles above.

When adding monitor credentials and notification channels:

- prefer PagerDuty/Slack/Telegram only for real actionable alerts
- do not notify on every single transient `healthz` blip
- route `statusz` symptom alerts separately from public outage alerts

## Operational Guidance

During deploys:

- use `/healthz` to confirm process start
- use `/readyz` to decide whether the instance can be put in rotation
- use `/statusz` if readiness fails and you need the failing subsystem immediately

During incident response:

- if `healthz` fails: app process is down or unreachable
- if `healthz` passes but `readyz` fails: the API is up but not operationally safe
- if `readyz` passes but queue alerts fire: traffic is reaching the API, but async subsystems are degrading
- if `statusz` shows provider misconfiguration: fix config first before debugging code paths

## Summary

- `healthz` is for liveness.
- `readyz` is the strict gate for traffic readiness.
- `statusz` is the detailed diagnostic snapshot.
- OpenStatus should monitor `healthz` publicly and `readyz` privately.
- `statusz` should feed operator diagnostics and backlog/provider alerting, not primary uptime checks.

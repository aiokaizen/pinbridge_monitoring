# Monitoring Notes

Deployment and server setup instructions live in [README.md](/home/mouadk/workspace/pinbridge/monitoring/README.md).

## Decisions

- Do not keep patching OpenStatus.
- Use Uptime Kuma for uptime checks and the public status page.
- Keep the stack operationally boring:
  - one container
  - one volume
  - `nginx` in front
- Monitor PinBridge primarily through the application's own health endpoints instead of trying to make the monitoring tool understand every internal subsystem.

## Endpoint Roles

### `GET /healthz`

Purpose:

- confirm the API process is alive
- stay cheap enough for high-frequency probes

What it checks:

- API process only

What it does not prove:

- database reachability
- Redis reachability
- worker availability
- asset storage writability

Use it for:

- public uptime probes
- basic smoke checks

### `GET /readyz`

Purpose:

- decide whether the API instance is actually fit to serve traffic

What it checks:

- database connectivity
- Redis connectivity
- worker/broker basics
- storage/runtime dependencies needed for normal operation

Use it for:

- internal or allowlisted uptime probes
- post-deploy smoke tests

### `GET /statusz`

Purpose:

- return a structured runtime snapshot for diagnosis

Use it for:

- low-frequency internal monitoring
- operator debugging
- alert enrichment

Do not use `statusz` as your main public uptime probe. It is more expensive and noisier than `healthz`.

## Monitoring Strategy

Use Kuma for:

- WebApp availability
- public API liveness
- internal API readiness if reachable from the monitoring server
- optional low-frequency `statusz`
- public status page publishing

Do not try to monitor every internal service directly from Kuma unless exposing those services is operationally justified. For Postgres, Redis, workers, and queues, it is usually better to let the API surface those conditions through `readyz` and `statusz`.

Recommended intervals:

- public HTTP checks: every `60s`
- readiness checks: every `60s`
- `statusz`: every `120s`

## Monitor Matrix

### Public checks

Website:

- URL: `https://www.pinbridge.io/`
- expectation: `200`
- purpose: public marketing-site availability

App:

- URL: `https://app.pinbridge.io/`
- expectation: `200` or expected login redirect
- purpose: actual product entrypoint

API liveness:

- URL: `https://api.pinbridge.io/healthz`
- expectation: `200`
- purpose: API process availability

### Internal or allowlisted checks

API readiness:

- URL: `https://api.pinbridge.io/readyz`
- expectation: `200`
- purpose: traffic-serving readiness

Detailed runtime snapshot:

- URL: `https://api.pinbridge.io/statusz`
- expectation: structured JSON
- purpose: diagnosis, not hot-path uptime

## Status Page Topology

Use two public domains:

- `openstatus.yourdomain.com` for the Kuma dashboard
- `status.yourdomain.com` for the public status page entry point

Both domains proxy to the same Kuma instance.

The status domain should redirect `/` to the selected Kuma status page slug:

- `/status/pinbridge`

If you rename the status page slug, update the `nginx` redirect to match.

## Alert Rules

Start with these alert rules:

1. Website down
   - trigger: 3 consecutive failures
   - severity: high

2. App down
   - trigger: 3 consecutive failures
   - severity: high

3. API liveness down
   - trigger: 3 consecutive failures
   - severity: high

4. API readiness failing
   - trigger: 2 consecutive failures
   - severity: high

5. `statusz` degraded
   - trigger: repeated failure or degraded payload inspection
   - severity: medium

Tune alerts after a week of real traffic. Do not overfit the first version.

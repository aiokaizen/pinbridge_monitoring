SHELL := /bin/sh

COMPOSE := docker compose --env-file .env
OPENSTATUS_SOURCE_DIR ?= ../openstatus
OPENSTATUS_BUILD_IMAGE ?= pinbridge-openstatus-workflows-build
MONITORING_NETWORK ?= pinbridge-monitoring-internal
LIBSQL_VOLUME ?= pinbridge-monitoring-libsql-data
WORKSPACE_ID ?= 1

.PHONY: help up rebuild restart logs ps \
	migrate-db db-workspaces db-pages db-monitors db-status-pages \
	workspace-team-plan workspace-team-limits private-location-restart \
	private-location-logs cron-1m cron-5m cron-10m cron-30m cron-1h \
	persistence-check

help:
	@printf '%s\n' \
	'Useful targets:' \
	'  make up                    - start the full monitoring stack' \
	'  make rebuild               - rebuild and recreate the full stack' \
	'  make restart               - restart the full stack containers' \
	'  make logs                  - tail compose logs' \
	'  make ps                    - show compose status' \
	'  make migrate-db            - run OpenStatus DB migrations via build image' \
	'  make db-workspaces         - list workspaces' \
	'  make db-monitors           - list monitors' \
	'  make db-pages              - list status page components/pages summary' \
	'  make db-status-pages       - list status pages' \
	'  make workspace-team-plan   - set workspace plan=team for WORKSPACE_ID' \
	'  make workspace-team-limits - unlock self-host limits incl private locations' \
	'  make private-location-restart - restart private-location after key update' \
	'  make private-location-logs - tail private-location logs' \
	'  make cron-1m              - manually trigger 1m monitor scheduler' \
	'  make cron-5m              - manually trigger 5m monitor scheduler' \
	'  make cron-10m             - manually trigger 10m monitor scheduler' \
	'  make cron-30m             - manually trigger 30m monitor scheduler' \
	'  make cron-1h              - manually trigger 1h monitor scheduler' \
	'  make persistence-check     - inspect the libsql named volume'

up:
	$(COMPOSE) up -d

rebuild:
	$(COMPOSE) up -d --build --force-recreate

restart:
	$(COMPOSE) restart

logs:
	$(COMPOSE) logs --tail 200

ps:
	$(COMPOSE) ps

migrate-db:
	docker build \
		-f $(OPENSTATUS_SOURCE_DIR)/apps/workflows/Dockerfile \
		--target build \
		-t $(OPENSTATUS_BUILD_IMAGE) \
		$(OPENSTATUS_SOURCE_DIR)
	docker run --rm \
		--network $(MONITORING_NETWORK) \
		-e DATABASE_URL=http://pinbridge-monitoring-libsql:8080 \
		-e DATABASE_AUTH_TOKEN= \
		-w /app/packages/db \
		$(OPENSTATUS_BUILD_IMAGE) \
		bun src/migrate.mts

db-workspaces:
	$(COMPOSE) exec -T server sh -lc 'curl -sS -X POST http://libsql:8080/ -H "Content-Type: application/json" -d '\''{"statements":["SELECT id, name, slug, plan, paid_until, ends_at FROM workspace;"]}'\'''

db-monitors:
	$(COMPOSE) exec -T server sh -lc 'curl -sS -X POST http://libsql:8080/ -H "Content-Type: application/json" -d '\''{"statements":["SELECT id, name, url, periodicity, active, status FROM monitor ORDER BY id;"]}'\'''

db-pages:
	$(COMPOSE) exec -T server sh -lc 'curl -sS -X POST http://libsql:8080/ -H "Content-Type: application/json" -d '\''{"statements":["SELECT id, page_id, name, monitor_id, sort_order FROM page_component ORDER BY page_id, sort_order, id;"]}'\'''

db-status-pages:
	$(COMPOSE) exec -T server sh -lc 'curl -sS -X POST http://libsql:8080/ -H "Content-Type: application/json" -d '\''{"statements":["SELECT id, title, slug, custom_domain, published FROM page ORDER BY id;"]}'\'''

workspace-team-plan:
	$(COMPOSE) exec -T server sh -lc 'curl -sS -X POST http://libsql:8080/ -H "Content-Type: application/json" -d '\''{"statements":["UPDATE workspace SET plan='\''team'\'', paid_until=strftime('\''%s'\'','\''now'\'') + 315360000, ends_at=NULL WHERE id=$(WORKSPACE_ID);","SELECT id, name, plan, paid_until, ends_at FROM workspace WHERE id=$(WORKSPACE_ID);"]}'\'''

workspace-team-limits:
	$(COMPOSE) exec -T server sh -lc 'curl -sS -X POST http://libsql:8080/ -H "Content-Type: application/json" -d '\''{"statements":["UPDATE workspace SET limits = '\''{\"monitors\":100,\"periodicity\":[\"30s\",\"1m\",\"5m\",\"10m\",\"30m\",\"1h\"],\"multi-region\":true,\"data-retention\":\"24 months\",\"status-pages\":20,\"maintenance\":true,\"status-subscribers\":true,\"custom-domain\":true,\"password-protection\":true,\"white-label\":true,\"notifications\":true,\"sms\":true,\"pagerduty\":true,\"notification-channels\":50,\"members\":\"Unlimited\",\"audit-log\":true,\"private-locations\":true}'\'' WHERE id=$(WORKSPACE_ID);","SELECT id, plan, limits FROM workspace WHERE id=$(WORKSPACE_ID);"]}'\'''

private-location-restart:
	$(COMPOSE) up -d private-location

private-location-logs:
	$(COMPOSE) logs private-location --tail 100

cron-1m:
	$(COMPOSE) exec -T workflows sh -lc 'curl -fsS -H "authorization: $$CRON_SECRET" http://localhost:3000/cron/checker/1m'

cron-5m:
	$(COMPOSE) exec -T workflows sh -lc 'curl -fsS -H "authorization: $$CRON_SECRET" http://localhost:3000/cron/checker/5m'

cron-10m:
	$(COMPOSE) exec -T workflows sh -lc 'curl -fsS -H "authorization: $$CRON_SECRET" http://localhost:3000/cron/checker/10m'

cron-30m:
	$(COMPOSE) exec -T workflows sh -lc 'curl -fsS -H "authorization: $$CRON_SECRET" http://localhost:3000/cron/checker/30m'

cron-1h:
	$(COMPOSE) exec -T workflows sh -lc 'curl -fsS -H "authorization: $$CRON_SECRET" http://localhost:3000/cron/checker/1h'

persistence-check:
	docker volume inspect $(LIBSQL_VOLUME)
	docker run --rm -v $(LIBSQL_VOLUME):/data alpine sh -lc 'ls -lah /data'

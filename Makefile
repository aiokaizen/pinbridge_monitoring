SHELL := /bin/sh

COMPOSE := docker compose --env-file .env
KUMA_CONTAINER ?= pinbridge-monitoring-kuma
KUMA_VOLUME ?= pinbridge-monitoring-kuma-data
BACKUP_DIR ?= backups

.PHONY: help up rebuild restart logs ps shell backup persistence-check compose-config

help:
	@printf '%s\n' \
	'Useful targets:' \
	'  make up                - start Uptime Kuma' \
	'  make rebuild           - recreate Uptime Kuma' \
	'  make restart           - restart the container' \
	'  make logs              - tail compose logs' \
	'  make ps                - show compose status' \
	'  make shell             - open a shell inside the Kuma container' \
	'  make backup            - create a tar.gz backup of the Kuma data volume' \
	'  make persistence-check - inspect the Kuma named volume' \
	'  make compose-config    - render the compose config with .env values'

up:
	$(COMPOSE) up -d

rebuild:
	$(COMPOSE) up -d --force-recreate

restart:
	$(COMPOSE) restart

logs:
	$(COMPOSE) logs --tail 200

ps:
	$(COMPOSE) ps

shell:
	$(COMPOSE) exec kuma sh

backup:
	mkdir -p $(BACKUP_DIR)
	docker run --rm \
		-v $(KUMA_VOLUME):/data \
		-v $(CURDIR)/$(BACKUP_DIR):/backup \
		alpine sh -lc 'tar -czf /backup/kuma-data-$$(date +%Y%m%d-%H%M%S).tar.gz -C /data .'

persistence-check:
	docker volume inspect $(KUMA_VOLUME)
	docker run --rm -v $(KUMA_VOLUME):/data alpine sh -lc 'ls -lah /data'

compose-config:
	$(COMPOSE) config

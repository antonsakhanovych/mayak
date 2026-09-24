COMPOSE := docker compose
ENV_FILE := .env
MC_ENV_FILE := mayak-mc/.env
BACKUP_ENV_FILE := mayak-backup/.env
CLOUDFLARED_CONFIG := mayak-cloudflared/config.yml
CLOUDFLARED_CREDS := mayak-cloudflared/credentials.json

# world data location - mirrors the compose default; override in .env or on the
# command line (make restore DATA_DIR=/path ...)
DATA_DIR := $(shell sed -n 's/^DATA_DIR=//p' $(ENV_FILE) 2>/dev/null | tail -n1 | sed 's/[ \t]*#.*//; s/[ \t]*$$//')
DATA_DIR := $(if $(DATA_DIR),$(DATA_DIR),./mayak-mc/data)

.DEFAULT_GOAL := help
.PHONY: help up down restart logs console cmd backup snapshots restore pull build smoke sync deploy cloudflared

help: ## list targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n",$$1,$$2}'

$(ENV_FILE):
	@echo "no $(ENV_FILE) - copy .env.example to .env and edit it"; exit 1

$(MC_ENV_FILE):
	@echo "no $(MC_ENV_FILE) - copy mayak-mc/.env.example to $(MC_ENV_FILE) and edit it"; exit 1

$(BACKUP_ENV_FILE):
	@echo "no $(BACKUP_ENV_FILE) - copy mayak-backup/.env.example to $(BACKUP_ENV_FILE) and edit it"; exit 1

$(CLOUDFLARED_CONFIG):
	@echo "no $(CLOUDFLARED_CONFIG) - copy mayak-cloudflared/config.yml.example to $(CLOUDFLARED_CONFIG) and edit it"; exit 1

$(CLOUDFLARED_CREDS):
	@echo "no $(CLOUDFLARED_CREDS) - copy your tunnel's credentials JSON to $(CLOUDFLARED_CREDS)"; exit 1

up: $(ENV_FILE) $(MC_ENV_FILE) $(BACKUP_ENV_FILE) $(CLOUDFLARED_CONFIG) $(CLOUDFLARED_CREDS) ## start everything, cloudflared included
	@mkdir -p "$(DATA_DIR)"
	$(COMPOSE) up -d --build

down: ## stop and remove containers
	$(COMPOSE) down

restart: ## restart the server container
	$(COMPOSE) restart server

logs: ## follow server logs
	$(COMPOSE) logs -f server

console: ## interactive RCON console
	$(COMPOSE) exec server rcon-cli

cmd: ## one RCON command: make cmd C="whitelist list"
	@test -n "$(C)" || { echo 'usage: make cmd C="say hello"'; exit 1; }
	$(COMPOSE) exec server rcon-cli $(C)

backup: ## run a backup cycle now
	$(COMPOSE) exec backup entrypoint.sh --once

snapshots: ## list cloud restic snapshots
	$(COMPOSE) exec backup restic snapshots --tag mayak

restore: $(ENV_FILE) ## restore $(DATA_DIR) from a snapshot (stop the server first): make restore SNAP=latest
	@test -n "$(SNAP)" || { echo 'usage: make restore SNAP=<id|latest>'; exit 1; }
	@printf 'overwrite %s from snapshot %s? [y/N] ' "$(DATA_DIR)" "$(SNAP)"; read a; [ "$$a" = y ] || exit 1
	@mkdir -p "$(DATA_DIR)"
	$(COMPOSE) run --rm --no-deps -v "$(abspath $(DATA_DIR)):/restore" backup \
	  restic restore "$(SNAP):/data" --tag mayak --target /restore
	@echo "done - run 'make up'"

pull: ## pull the latest server image
	$(COMPOSE) pull server

build: ## build the mayak-backup image
	$(COMPOSE) build

cloudflared: $(CLOUDFLARED_CONFIG) $(CLOUDFLARED_CREDS) ## (re)start just the tunnel container, e.g. after editing its config
	$(COMPOSE) up -d cloudflared

sync: ## [dev machine] rsync the project to a host: make sync [HOST=user@host]
	./sync.sh $(HOST)

deploy: $(ENV_FILE) $(MC_ENV_FILE) $(BACKUP_ENV_FILE) $(CLOUDFLARED_CONFIG) $(CLOUDFLARED_CREDS) ## [target host] pull + build + (re)start after a sync
	@mkdir -p "$(DATA_DIR)"
	$(COMPOSE) pull server
	$(COMPOSE) up -d --build

smoke: up ## up -> wait healthy -> one backup -> list snapshots
	@echo "waiting for health..."
	@for i in $$(seq 1 60); do \
	  h=$$(docker inspect -f '{{.State.Health.Status}}' mayak 2>/dev/null || true); \
	  [ "$$h" = healthy ] && { echo "healthy"; break; }; \
	  sleep 5; \
	done
	$(COMPOSE) exec backup entrypoint.sh --once
	$(COMPOSE) exec backup restic snapshots --tag mayak

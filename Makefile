COMPOSE := docker compose
ENV_FILE := .env

.DEFAULT_GOAL := help
.PHONY: help up down restart logs console cmd backup snapshots restore pull build smoke

help: ## list targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n",$$1,$$2}'

$(ENV_FILE):
	@echo "no $(ENV_FILE) - copy .env.example to .env and edit it"; exit 1

up: $(ENV_FILE) ## start server + backup sidecar
	@mkdir -p data
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

restore: ## restore ./data from a snapshot (stop the server first): make restore SNAP=latest
	@test -n "$(SNAP)" || { echo 'usage: make restore SNAP=<id|latest>'; exit 1; }
	@printf 'overwrite ./data from snapshot %s? [y/N] ' "$(SNAP)"; read a; [ "$$a" = y ] || exit 1
	$(COMPOSE) run --rm --no-deps -v "$(CURDIR)/data:/restore" backup \
	  restic restore "$(SNAP):/data" --tag mayak --target /restore
	@echo "done - run 'make up'"

pull: ## pull the latest server image
	$(COMPOSE) pull server

build: ## build the backup image
	$(COMPOSE) build

smoke: up ## up -> wait healthy -> one backup -> list snapshots
	@echo "waiting for health..."
	@for i in $$(seq 1 60); do \
	  h=$$(docker inspect -f '{{.State.Health.Status}}' mayak 2>/dev/null || true); \
	  [ "$$h" = healthy ] && { echo "healthy"; break; }; \
	  sleep 5; \
	done
	$(COMPOSE) exec backup entrypoint.sh --once
	$(COMPOSE) exec backup restic snapshots --tag mayak

IMAGE   ?= asolopovas/franken-php
TAG     ?= latest
DC      := docker compose

.PHONY: help test test-integration test-all lint build push pull \
        up down stop restart ps logs \
        shell fish mysql redis-cli \
        rebuild clean nuke \
        health db-backup db-restore install

help:
	@printf "\033[1mUsage:\033[0m make \033[36m<target>\033[0m\n\n"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build franken-php image
	docker build -t $(IMAGE):$(TAG) ./franken_php

push: build ## Build and push image to registry
	docker push $(IMAGE):$(TAG)

pull: ## Pull image from registry
	docker pull $(IMAGE):$(TAG)

up: ## Start all services
	$(DC) up -d

down: ## Stop and remove containers
	$(DC) down

stop: ## Stop running containers
	$(DC) stop

restart: ## Restart all services
	$(DC) restart

rebuild: ## Rebuild and recreate containers
	$(DC) build && $(DC) up -d --force-recreate

rebuild-no-cache: ## Full rebuild without cache
	$(DC) build --no-cache && $(DC) up -d --force-recreate

ps: ## Show container status
	$(DC) ps --format "table {{.Name}}\t{{.Service}}\t{{.Status}}\t{{.Ports}}"

logs: ## Tail logs for all services
	$(DC) logs -f --tail=100

logs-%: ## Tail logs for a service (e.g. make logs-mariadb)
	$(DC) logs -f --tail=100 $*

health: ## Show service health status
	@$(DC) ps --format "table {{.Service}}\t{{.Status}}" | head -1
	@$(DC) ps --format "table {{.Service}}\t{{.Status}}" | tail -n +2 | sort

top: ## Display running processes
	$(DC) top

shell: ## Bash shell in franken_php
	$(DC) exec franken_php bash

fish: ## Fish shell in franken_php
	$(DC) exec franken_php fish

mysql: ## MySQL client as root
	$(DC) exec mariadb mariadb -uroot -psecret

redis-cli: ## Redis CLI
	$(DC) exec redis redis-cli

redis-flush: ## Flush all Redis data
	$(DC) exec redis redis-cli flushall

redis-monitor: ## Monitor Redis commands
	$(DC) exec redis redis-cli monitor

db-backup: ## Dump all databases to db-backup.sql.gz
	$(DC) exec mariadb mariadb-dump -uroot -psecret --all-databases | gzip > db-backup.sql.gz
	@printf "Backed up to db-backup.sql.gz\n"

db-restore: ## Restore from db-backup.sql.gz
	@test -f db-backup.sql.gz || (printf "db-backup.sql.gz not found\n" && exit 1)
	gunzip -c db-backup.sql.gz | $(DC) exec -T mariadb mariadb -uroot -psecret
	@printf "Restore complete\n"

clean: down ## Remove containers, networks, and volumes
	$(DC) down --remove-orphans -v

nuke: ## Remove everything including images
	$(DC) down --rmi all --remove-orphans -v

prune: ## Remove dangling images and build cache
	docker image prune -f
	docker builder prune -f

install: ## Symlink web CLI and fish completions
	@mkdir -p $(HOME)/.local/bin $(HOME)/.config/fish/completions
	ln -sf $(CURDIR)/web.sh $(HOME)/.local/bin/web
	ln -sf $(CURDIR)/web.completions.fish $(HOME)/.config/fish/completions/web.fish
	@printf "Installed: web -> %s/web.sh\n" $(CURDIR)

test: ## Run unit tests
	@bats tests/unit/

test-integration: ## Run integration tests (requires running services)
	@bats tests/integration/

test-all: ## Run all tests (integration if services are up)
	@bash tests.sh

lint: ## Run shellcheck on web.sh
	@shellcheck -x -e SC2086,SC2016,SC2034,SC2029,SC2120,SC2119,SC2318 -S warning web.sh

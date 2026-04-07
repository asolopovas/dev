IMAGE   ?= asolopovas/franken-php
TAG     ?= latest

.PHONY: help build push pull install test test-integration test-all lint

help:
	@printf "\033[1mUsage:\033[0m make \033[36m<target>\033[0m\n\n"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build franken-php image
	docker build -t $(IMAGE):$(TAG) ./franken_php

push: build ## Build and push image to registry
	docker push $(IMAGE):$(TAG)

pull: ## Pull image from registry
	docker pull $(IMAGE):$(TAG)

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

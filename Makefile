IMAGE   ?= asolopovas/franken-php
TAG     ?= latest

.PHONY: help build push pull install install-go test test-go test-integration test-all lint build-go

help:
	@printf "\033[1mUsage:\033[0m make \033[36m<target>\033[0m\n\n"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build franken-php image
	docker build -t $(IMAGE):$(TAG) ./franken_php

push: build ## Build and push image to registry
	docker push $(IMAGE):$(TAG)

pull: ## Pull image from registry
	docker pull $(IMAGE):$(TAG)

install: build-go ## Install Go web CLI to /usr/local/bin/web
	@$(CURDIR)/bin/web install

build-go: ## Build Go web CLI
	@mkdir -p bin
	go build -o bin/web ./cmd/web

install-go: install ## Install Go web CLI to /usr/local/bin/web

test: ## Run unit tests
	@bats tests/unit/

test-go:
	@go test ./...

test-integration: ## Run integration tests (requires running services)
	@bats tests/integration/

test-all: ## Run all tests (integration if services are up)
	@bash tests.sh

lint: ## Run shellcheck on web.sh
	@shellcheck -x -e SC2086,SC2016,SC2034,SC2029,SC2120,SC2119,SC2318 -S warning web.sh

IMAGE   ?= asolopovas/franken-php
TAG     ?= latest

.PHONY: help build push pull install install-go test test-go test-integration test-all lint

help:
	@printf "\033[1mUsage:\033[0m make \033[36m<target>\033[0m\n\n"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build franken-php image
	docker build -t $(IMAGE):$(TAG) ./franken_php

push: build ## Build and push image to registry
	docker push $(IMAGE):$(TAG)

pull: ## Pull image from registry
	docker pull $(IMAGE):$(TAG)

install: install-go ## Install Go web CLI to /usr/local/bin/web

install-go: ## Build and install Go web CLI to /usr/local/bin/web
	@mkdir -p bin
	go build -o bin/web ./cmd/web
	@$(CURDIR)/bin/web install

test: test-go ## Run unit tests

test-go:
	@go test ./...

test-integration: ## Run integration tests (requires running services)
	@bats tests/integration/

test-all: ## Run all tests (integration if services are up)
	@bash tests.sh

lint: ## Check Go formatting, vet, and shell scripts
	@[ -z "$$(gofmt -l cmd internal)" ] || { gofmt -l cmd internal; exit 1; }
	@go vet ./...
	@shellcheck tests.sh franken_php/entrypoint.sh

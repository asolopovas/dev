IMAGE   ?= asolopovas/franken-php
TAG     ?= latest

.PHONY: test build push pull

test:
	@bash tests.sh

build:
	docker build -t $(IMAGE):$(TAG) ./franken_php

push: build
	docker push $(IMAGE):$(TAG)

pull:
	docker pull $(IMAGE):$(TAG)

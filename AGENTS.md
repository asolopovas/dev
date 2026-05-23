# AGENTS.md

Compact guidance for coding agents. Keep this file short; detailed project knowledge lives under [`docs/`](./docs/).

## Project

`web` is a Go CLI for a Docker-based PHP development environment for local WordPress and Laravel work. It orchestrates FrankenPHP/Caddy/PHP 8.4, MariaDB, Redis, PhpMyAdmin, Mailpit, Typesense, local hostnames, SSL, database provisioning, and site scaffolding.

## Read next

| Need | Source of truth |
|---|---|
| User setup, commands, services, SSL, databases, troubleshooting | [`docs/OPERATIONS.md`](./docs/OPERATIONS.md) |
| Runtime architecture, generated files, host config, WSL flow | [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) |
| Tests, linting, style, safe edit rules, known traps | [`docs/ENGINEERING.md`](./docs/ENGINEERING.md) |
| Documentation map and maintenance rules | [`docs/README.md`](./docs/README.md) |

## Non-negotiables

- Do not add comments to code. No inline, trailing, block, YAML, Dockerfile, Bash, or config comments.
- Unit tests must not call real Docker, mutate `/etc/hosts`, or mutate the Windows hosts file.
- Keep `web-hosts.json` writes atomic through `SaveRegistry()`.
- `rebuildWebConfiguration` must batch host redirects through `addHostRedirects`.
- Do not add per-service Docker status probes in status rendering; prefer a single Compose `ps` call.
- PHP `.ini` files use native `${ENV_VAR}` interpolation. Do not replace this with runtime rewrites.
- Generated files are outputs, not hand-maintained sources.

## Validation

```sh
make lint
make test
make test-integration
```

Run `make test-integration` only when the Docker services required by the integration tests are available.

## Common commands

```sh
web up
web build [service] [--no-cache]
web new-host example.test -t wp
web new-host api.test -t laravel
web remove-host example.test
web build-webconf
web debug debug
web bash
```

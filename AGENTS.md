# AGENTS.md

Compact guidance for coding agents. Keep this file short; detailed project knowledge lives under [`docs/`](./docs/).

## Project

`web.sh` is a Docker-based PHP development environment for local WordPress and Laravel work. A single Bash CLI orchestrates FrankenPHP/Caddy/PHP 8.4, MariaDB, Redis, PhpMyAdmin, Mailpit, Typesense, local hostnames, SSL, database provisioning, and site scaffolding.

## Read next

| Need | Source of truth |
|---|---|
| User setup, commands, services, SSL, databases, troubleshooting | [`docs/OPERATIONS.md`](./docs/OPERATIONS.md) |
| Runtime architecture, generated files, host config, WSL flow | [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) |
| Tests, linting, style, safe edit rules, known traps | [`docs/ENGINEERING.md`](./docs/ENGINEERING.md) |
| Documentation map and maintenance rules | [`docs/README.md`](./docs/README.md) |

## Non-negotiables

- Do not add comments to code. No inline, trailing, block, YAML, Dockerfile, Bash, or config comments.
- Keep `web.sh` sourceable. Do not break the `if [[ "${BASH_SOURCE[0]}" == "$0" ]]` guard.
- Unit tests must not call real Docker, mutate `/etc/hosts`, or mutate the Windows hosts file.
- Use the existing `hosts_json_*` helpers for `web-hosts.json`; keep writes atomic through `hosts_json_write()`.
- `build_webconf` must batch host redirects through `redirect_add_batch`.
- `dc_ps` should keep the single `$DC ps --format json` fast path, not per-service status calls.
- PHP `.ini` files use native `${ENV_VAR}` interpolation. Do not replace this with runtime `sed` rewrites.
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
./web.sh up
./web.sh build [service] [--no-cache]
./web.sh new-host example.test -t wp
./web.sh new-host api.test -t laravel
./web.sh remove-host example.test
./web.sh build-webconf
./web.sh debug debug
./web.sh bash
```

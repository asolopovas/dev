# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## Project Overview

**web.sh** is a Docker-based PHP development environment for local WordPress and Laravel development. It orchestrates FrankenPHP (Caddy + PHP 8.4), MariaDB, Redis, PhpMyAdmin, Mailpit, and Typesense via Docker Compose, with automated SSL, host redirection, database provisioning, and project scaffolding through a single CLI.

## Commands

### Testing & Lint
```bash
make test                       # unit tests only (bats tests/unit/)
make test-integration           # integration tests (requires services running)
make test-all                   # tests.sh: unit + integration if franken_php is up
make lint                       # shellcheck with project-specific exclusions
bats tests/unit/main.bats       # run a single test file
bats -f "main help" tests/unit/ # filter by test name
```
CI runs `make lint` then `make test` on push/PR to `main` (`.github/workflows/ci.yml`). The lint target disables specific shellcheck codes (`SC2086,SC2016,SC2034,SC2029,SC2120,SC2119,SC2318`) — match those exclusions when adding new code.

Tests use [bats](https://github.com/bats-core/bats-core). `tests/test_helper.bash` sources `web.sh` (via the `BASH_SOURCE != $0` guard at the bottom of `web.sh`), redirects all path globals (`SCRIPT_DIR`, `WEB_ROOT`, `BACKEND_*`, `HOSTS_JSON`, `CERTS_DIR`, `SUPERVISOR_DIR`) into a temp dir, and overrides these stubs after sourcing: `_has_gum`, `select_option`, `spin`, `redirect_remove`, `redirect_add`, `db_remove`, `db_exists`, `db_create`. New unit tests must work with these stubs — never call real Docker or touch `/etc/hosts`.

### Common CLI Usage
```bash
./web.sh up                              # start all services
./web.sh build [service] [--no-cache]    # rebuild images
./web.sh new-host example.test -t wp     # create WordPress site
./web.sh new-host api.test -t laravel    # create Laravel project
./web.sh remove-host example.test        # remove site
./web.sh build-webconf                   # regenerate all Caddy configs
./web.sh debug debug                     # enable Xdebug
./web.sh bash                            # shell into container
```

## Architecture

### Single-script CLI (`web.sh`)

All logic lives in one bash script (~888 lines) with `set -o errexit` and `set -o pipefail`. The `main()` function dispatches commands via a `case` statement. The script can be both executed directly and sourced (for testing) — controlled by the `if [[ "${BASH_SOURCE[0]}" == "$0" ]]` guard at the end. Do not break that guard or tests will execute `main` on source.

### Configuration-driven host management

`web-hosts.json` is the central configuration store. It holds an array of host entries (`name`, `type`, `db`) plus paths for output directories, templates, and web root. All JSON manipulation goes through `hosts_json_*()` helper functions using `jq`. The `hosts_json_write()` pattern atomically writes via temp file + `mv`.

### Auto-generated files (gitignored)

When `build_webconf` runs, it generates per-host files from templates:
- `franken_php/config/sites/*.conf` — Caddy server blocks from `template.conf`
- `franken_php/config/ssl/*.key|.crt|.csr` — SSL certificates per host
- `templates.yml` — Docker Compose network aliases
- `crontab` — WordPress cron schedule for Supercronic

### Database naming convention

`make_db_name()` extracts the main domain, handles known second-level domains (`co.uk`, `gov.uk`, `com.br`, `co.jp`), and appends `_wp` or `_db` based on site type. Each host gets an isolated database and user with the same name.

### Interactive UI via `gum`

The script uses [gum](https://github.com/charmbracelet/gum) for styled prompts, spinners, and live service status tables. All gum calls have non-interactive fallbacks (plain printf). `dc_live_action()` renders a live-updating table showing per-service restart progress.

### WSL support

Host redirection works on both native Linux (`/etc/hosts`) and WSL (Windows hosts file via PowerShell `Hosts` module). WSL detection uses `/proc/version`. The `_resolve_hosts_module_path()` function caches the PowerShell module path.

### Docker service layout

The `franken_php` container is the main service — it runs Caddy as PID 1 with PHP 8.4, plus Node.js (Volta), Bun, Composer, and Supercronic. The `entrypoint.sh` handles Xdebug configuration and cron setup at container start. MariaDB uses a health check; the app service depends on it.

## Code Style

- **No comments in code.** Never add inline comments, block comments, or any other form of code commentary. The code must speak for itself through clear naming and structure. This applies to all file types (bash, YAML, Dockerfile, conf, etc.).

## Key Patterns

- **Error handling**: `die()` for fatal errors (exits 1), `warn()` for non-fatal, `require_*()` for precondition checks
- **Spin wrappers**: `spin "message" command args...` shows a gum spinner or falls back to plain logging
- **Docker Compose**: all DC calls go through `$DC` variable (`docker compose -f $SCRIPT_DIR/docker-compose.yml`)
- **Test isolation**: tests source `web.sh`, then stub out external dependencies (`_has_gum`, `select_option`, `spin`, `redirect_remove`, `redirect_add`, `db_remove`, `db_exists`, `db_create`) to run purely in-memory

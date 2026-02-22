# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## Project Overview

**web.sh** is a Docker-based PHP development environment for local WordPress and Laravel development. It orchestrates FrankenPHP (Caddy + PHP 8.4), MariaDB, Redis, PhpMyAdmin, Mailhog, and Typesense via Docker Compose, with automated SSL, host redirection, database provisioning, and project scaffolding through a single CLI.

## Commands

### Testing
```bash
make test              # run unit tests
make test-integration  # run integration tests (requires running services)
make test-all          # run all tests
bash tests.sh          # direct execution (equivalent to test-all)
```
Tests use [bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System). Each test gets an isolated temp directory via `common_setup`/`common_teardown` in `tests/test_helper.bash`. Unit tests stub external dependencies (Docker, gum, host redirects) to run purely in-memory. Integration tests require running services.

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

No linter is configured. Use `shellcheck web.sh` for static analysis if needed.

## Architecture

### Single-script CLI (`web.sh`, ~900 lines)

All logic lives in one bash script with `set -o errexit` and `set -o pipefail`. The `main()` function at line ~863 dispatches commands via a `case` statement. The script can be both executed directly and sourced (for testing) — controlled by the `if [[ "${BASH_SOURCE[0]}" == "$0" ]]` guard at the end.

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

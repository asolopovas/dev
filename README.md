# web.sh

Docker-based PHP development environment for WordPress and Laravel.

## Features

- **FrankenPHP** (Caddy + PHP 8.4), MariaDB, Redis, PhpMyAdmin, Mailpit, Typesense
- Optional self-signed SSL with custom root CA (HTTP serves by default)
- WordPress/Laravel scaffolding with database provisioning
- Local domain redirection (Linux + WSL, batched UAC prompts)
- Fish shell completions, Xdebug with `${ENV_VAR}` ini interpolation
- Node.js, Bun, Composer, Supercronic, ripgrep/fd/fzf inside the container

## Quick Start

```sh
web install                          # symlink CLI + fish completions
web new-host example.test -t wp      # create WordPress site
web new-host api.test -t laravel     # create Laravel project
web up                               # start services
```

## Commands

| Command | Description |
|---|---|
| `up/stop/restart [service]` | Manage Docker services |
| `down` | Stop and remove the entire stack |
| `build [service] [--no-cache]` | Build Docker images |
| `ps [service]` | Container status (gum table) |
| `log <service>` | Service logs |
| `new-host [host] [-t type]` | Create site (wizard or flags) |
| `remove-host [host]` | Remove site (interactive multi-select or by name) |
| `build-webconf` | Regenerate Caddy configs |
| `bash` / `fish` | Container shell access |
| `rootssl` | Generate root CA |
| `hostssl <host>` | Generate host SSL certificate |
| `import-rootca` | Import root CA to Chrome (Linux) |
| `mysql` | MariaDB client as root |
| `db-backup` / `db-restore` | Dump/restore all databases |
| `redis-cli` / `redis-flush` / `redis-monitor` | Redis management |
| `debug [off\|debug\|profile]` | Set Xdebug mode |
| `install` | Create CLI and Fish completion symlinks |
| `dir` | Print script directory |

## Docker Services

| Service | Ports |
|---|---|
| **franken_php** - PHP 8.4 + Caddy + Xdebug | 80, 443, 443/udp, 8080 |
| **mariadb** - MySQL compatible | 3306 |
| **redis** | 6379 |
| **phpmyadmin** | via Caddy |
| **mailpit** | 1025 (SMTP), 8025 (UI) |
| **typesense** | 8108 |

## Project Structure

```
web.sh                  Main CLI
docker-compose.yml      Service definitions
web-hosts.json          Host configuration (gitignored)
franken_php/            PHP service (Dockerfile, Caddy configs, SSL certs)
mariadb/                Database service
redis/                  Cache service
```

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `MAPDIR` | `..` | Web root mapping |
| `MYSQL_ROOT_PASSWORD` | `secret` | DB root password |
| `XDEBUG_MODE` | `debug` | Xdebug mode (PHP reads via `${XDEBUG_MODE}` interpolation) |

## Make Targets

| Target | Description |
|---|---|
| `make build` | Build franken-php image |
| `make push` | Build and push image to registry |
| `make pull` | Pull image from registry |
| `make install` | Symlink web CLI and fish completions |
| `make test` | Run unit tests |
| `make test-integration` | Run integration tests (services must be up) |
| `make test-all` | Unit + integration if franken_php is running |
| `make lint` | Run shellcheck on web.sh |

All runtime ops (up/down/ps/logs/shell/db-backup/etc.) live in `web.sh` only.

## Requirements

Docker, Docker Compose, jq, curl, tar, openssl, gum. Fish shell optional for completions.

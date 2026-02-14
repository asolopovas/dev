# web.sh

Docker-based PHP development environment for WordPress and Laravel.

## Features

- **FrankenPHP** (Caddy + PHP 8.4), MariaDB, Redis, PhpMyAdmin, Mailpit, Typesense
- Automatic SSL with custom root CA and HTTP/3 support
- WordPress/Laravel scaffolding with database provisioning
- Local domain redirection (Linux + WSL)
- Fish shell completions, Xdebug, Supervisor for Horizon
- Node.js via Volta with npm and Bun

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
| `up/down/stop/restart [service]` | Manage Docker services |
| `build [service] [--no-cache]` | Build Docker images |
| `ps [service]` | Container status |
| `log <service>` | Service logs |
| `new-host [host] [-t type]` | Create site (wizard or flags) |
| `remove-host <host>` | Remove site completely |
| `build-webconf` | Regenerate Caddy configs |
| `bash` / `fish` | Container shell access |
| `rootssl` | Generate root CA |
| `hostssl <host>` | Generate host SSL certificate |
| `import-rootca` | Import root CA to Chrome (Linux) |
| `redis-flush` / `redis-monitor` | Redis management |
| `debug <off\|debug\|profile>` | Set Xdebug mode |
| `supervisor-init` | Initialize user-level Supervisor |
| `supervisor-conf <host>` | Generate Horizon supervisor config |
| `supervisor-restart` | Restart Supervisor |
| `install` | Create CLI and Fish completion symlinks |
| `dir` | Print script directory |
| `git-update <user> <theme> [plugin]` | Git pull on lyntouch.com |

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
web-hosts.json          Host configuration
franken_php/            PHP service (Dockerfile, Caddy configs, SSL certs)
mariadb/                Database service
redis/                  Cache service
```

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `MAPDIR` | `..` | Web root mapping |
| `MYSQL_ROOT_PASSWORD` | `secret` | DB root password |
| `XDEBUG_MODE` | `off` | Xdebug mode |
| `NODE_VERSION` | `22.16.0` | Node.js version |

## Make Targets

| Target | Description |
|---|---|
| `make build` | Build franken-php image |
| `make push` | Build and push image to registry |
| `make pull` | Pull image from registry |
| `make up` | Start all services |
| `make down` | Stop and remove containers |
| `make stop` | Stop running containers |
| `make restart` | Restart all services |
| `make rebuild` | Rebuild and recreate containers |
| `make rebuild-no-cache` | Full rebuild without cache |
| `make ps` | Show container status |
| `make logs` | Tail logs for all services |
| `make logs-<service>` | Tail logs for a specific service |
| `make health` | Show service health status |
| `make top` | Display running processes |
| `make shell` | Bash shell in franken_php |
| `make fish` | Fish shell in franken_php |
| `make mysql` | MySQL client as root |
| `make redis-cli` | Redis CLI |
| `make redis-flush` | Flush all Redis data |
| `make redis-monitor` | Monitor Redis commands |
| `make db-backup` | Dump all databases to db-backup.sql.gz |
| `make db-restore` | Restore from db-backup.sql.gz |
| `make clean` | Remove containers, networks, and volumes |
| `make nuke` | Remove everything including images |
| `make prune` | Remove dangling images and build cache |
| `make install` | Symlink web CLI and fish completions |
| `make test` | Run test suite |

## Requirements

Docker, Docker Compose, jq, curl, tar, openssl. Fish shell optional for completions.

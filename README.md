# web.sh

Docker-based PHP development environment for WordPress and Laravel. One CLI manages the stack, scaffolds sites, wires up local DNS, and issues SSL certificates from a local root CA.

**License:** MIT · **Shell:** Bash (Fish completions optional) · **Platforms:** Linux, WSL2

## Features

- **FrankenPHP** (Caddy + PHP 8.4) with Xdebug, MariaDB, Redis, PhpMyAdmin, Mailpit, Typesense
- Optional self-signed SSL with a custom root CA (HTTP serves by default)
- WordPress and Laravel scaffolding with automatic database provisioning
- Local domain redirection on Linux and WSL (single batched UAC prompt on Windows)
- Node.js, Bun, Composer, Supercronic, ripgrep/fd/fzf preinstalled in the container
- PHP ini values use native `${ENV_VAR}` interpolation — no runtime sed

## Requirements

Docker, Docker Compose, `jq`, `curl`, `tar`, `openssl`, [`gum`](https://github.com/charmbracelet/gum). Fish shell optional for completions. For contributing: `bats-core`, `shellcheck`.

## Quick Start

```sh
git clone https://github.com/asolopovas/dev.git web && cd web
cp .env.example .env
./web.sh install                     # symlink CLI + fish completions
web new-host example.test -t wp      # scaffold WordPress site
web new-host api.test    -t laravel  # scaffold Laravel project
web up                               # start services
```

Then open `http://example.test`. Run `web rootssl && web import-rootca` once if you want trusted HTTPS.

## Commands

| Command | Description |
|---|---|
| `up` / `stop` / `restart` `[service]` | Manage Docker services |
| `down` | Stop and remove the entire stack |
| `build [service] [--no-cache]` | Build Docker images |
| `ps [service]` | Container status (gum table) |
| `log <service>` | Tail service logs |
| `new-host [host] [-t wp\|laravel]` | Create site (wizard or flags) |
| `remove-host [host]` | Remove site (multi-select or by name) |
| `build-webconf` | Regenerate Caddy configs |
| `bash` / `fish` | Container shell access |
| `rootssl` | Generate local root CA |
| `hostssl <host>` | Issue a host certificate |
| `import-rootca` | Trust the root CA in Chrome (Linux) |
| `mysql` | MariaDB client as root |
| `db-backup` / `db-restore` | Dump / restore all databases |
| `redis-cli` / `redis-flush` / `redis-monitor` | Redis management |
| `debug [off\|debug\|profile]` | Set Xdebug mode |
| `install` | Symlink CLI and Fish completions |
| `dir` | Print script directory |

## Services

| Service | Image | Ports |
|---|---|---|
| `franken_php` (Caddy + PHP 8.4 + Xdebug) | `dunglas/frankenphp:1.11.1-php8.4` | 80, 443, 443/udp, 8080 |
| `mariadb` | `mariadb:lts` | 3306 |
| `redis` | `redis:7.4.2-bookworm` | 6379 |
| `phpmyadmin` (reverse-proxied by Caddy at `phpmyadmin.test`) | `phpmyadmin:fpm-alpine` | — |
| `mailpit` | `axllent/mailpit` | 1025 (SMTP), 8025 (UI) |
| `typesense` | `typesense/typesense:29.0` | 8108 |

## Configuration

Edit `.env` (see `.env.example`):

| Variable | Default | Purpose |
|---|---|---|
| `MAPDIR` | `..` | Web root mapping |
| `MYSQL_ROOT_PASSWORD` | `secret` | DB root password |
| `REDIS_PASSWORD` | `redis` | Redis auth |
| `XDEBUG_MODE` | `debug` | `off`, `debug`, or `profile` |
| `XDEBUG_IDEKEY` | `XDEBUG_ECLIPSE` | IDE key |
| `XDEBUG_HOST` | `host.docker.internal` | Debugger host |
| `UID` / `GID` | `1000` | Container user mapping |

## Project Structure

```
web.sh                  Main CLI
docker-compose.yml      Service definitions
Makefile                Build / test / lint targets
web-hosts.json          Host configuration (gitignored)
franken_php/            Dockerfile, Caddy configs, SSL certs
mariadb/  redis/        Service configs
tests/                  Bats test suite (unit + integration)
AGENTS.md               Contributor guide
```

## Testing & Contributing

```sh
make lint               # shellcheck
make test               # bats unit tests
make test-integration   # requires services running
```

Read [AGENTS.md](./AGENTS.md) before making changes — notably the **no-comments-in-code** rule and the test-stub conventions in `tests/test_helper.bash`.

## Troubleshooting

- **Port 80/443 in use** — stop host-level nginx/apache or change the Caddy ports in `docker-compose.yml`.
- **WSL hosts file not updating** — accept the single UAC prompt; `build-webconf` batches all hosts into one PowerShell elevation.
- **Browser shows untrusted SSL** — run `web rootssl` once, then `web import-rootca` (Chrome on Linux). Restart the browser.
- **Xdebug not connecting** — confirm `XDEBUG_HOST=host.docker.internal` and the IDE is listening on 9003 with key `XDEBUG_ECLIPSE`.
- **`gum` not found** — install from https://github.com/charmbracelet/gum; the CLI falls back to plain prompts but tables look nicer with it.

## License

MIT — see [LICENSE](./LICENSE).

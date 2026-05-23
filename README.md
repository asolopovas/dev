# web

Docker-based PHP development environment for local WordPress and Laravel work. The Go CLI manages Docker Compose services, local hostnames, optional SSL certificates, database provisioning, and project scaffolding.

**License:** MIT · **Runtime:** Go + Docker Compose · **Platforms:** Linux, WSL2

## What it includes

- FrankenPHP with Caddy, PHP 8.4, Xdebug, Composer, Node.js, Bun, Supercronic, ripgrep, fd, and fzf
- MariaDB, Redis, PhpMyAdmin, Mailpit, and Typesense
- WordPress and Laravel host scaffolding with per-site databases
- Local hostname redirection for Linux and WSL2
- Optional local root CA and host certificates
- Go unit tests and Bats integration tests

## Requirements

Required: Go, Docker, Docker Compose, Bash, `curl`, and `tar`.

Recommended: Fish for completions and `bats-core` for integration tests. `openssl` is needed only when HTTPS certificates are enabled or generated manually.

Laravel scaffolding also expects `composer` on the host.

## Quick start

```sh
mkdir -p "$HOME/www"
git clone https://github.com/asolopovas/dev.git "$HOME/www/dev"
cd "$HOME/www/dev"
cp .env.example .env
make install
web up
web build-webconf
web new-host example.test -t wp
```

Open `http://example.test`.

HTTPS is disabled by default. To enable generated local certificates, set `"https": true` in `web-hosts.json`, run `web build-webconf`, then run `web import-rootca` once and restart the browser.

`make install` builds the Go CLI and installs it as `/usr/local/bin/web`. When elevated permissions are needed it prompts through terminal `sudo` first, which works in WSL terminals, then falls back to non-interactive sudo/askpass. Without installation, replace `web` with `go run ./cmd/web`. The default paths assume the checkout lives at `$HOME/www/dev` and projects live under `$HOME/www`.

## Common commands

| Command | Purpose |
|---|---|
| `web up [service]` | Start all services or one service and remove stale Compose orphans |
| `web stop [service]` | Stop all services or one service |
| `web restart [service]` | Restart all services or one service |
| `web down` | Stop and remove the stack |
| `web build [service] [--no-cache]` | Build images and recreate containers |
| `web ps [service]` | Show container status |
| `web log <service>` | Follow service logs |
| `web new-host [host] [-t wp\|laravel]` | Create a WordPress or Laravel site |
| `web remove-host [host]` | Remove a site, database, certs, and host mapping |
| `web build-webconf` | Regenerate generated Caddy, optional SSL, cron, and alias files |
| `web bash` / `web fish` | Open a shell in `franken_php` |
| `web mysql` | Open MariaDB as root |
| `web db-backup` / `web db-restore` | Dump or restore all databases |
| `web redis-cli` / `web redis-flush` / `web redis-monitor` | Manage Redis |
| `web debug [off\|debug\|profile]` | Change Xdebug mode |

See [docs/OPERATIONS.md](./docs/OPERATIONS.md) for full operating notes.

## Service endpoints

| Service | Endpoint |
|---|---|
| FrankenPHP / Caddy | `http://<host>`, optional `https://<host>`, ports 80/443/8080 |
| MariaDB | `127.0.0.1:3306` |
| Redis | `127.0.0.1:6379` |
| PhpMyAdmin | `http://phpmyadmin.test` |
| Mailpit | SMTP `127.0.0.1:1025`, UI `http://127.0.0.1:8025` |
| Typesense | `http://127.0.0.1:8108`, API key `xyz` |

## Project map

| Path | Role |
|---|---|
| `cmd/web`, `internal/web` | Go CLI and orchestration logic |
| `docker-compose.yml` | Local service graph |
| `franken_php/` | PHP/Caddy image, entrypoint, config, templates, cert output |
| `mariadb/`, `redis/` | Service configuration |
| `tests/` | Bats unit and integration tests |
| `docs/` | Maintained project knowledge base |
| `AGENTS.md` | Compact agent entry point and documentation map |

## Contributing

```sh
make lint
make test
make test-integration
```

Read [AGENTS.md](./AGENTS.md) first, then [docs/ENGINEERING.md](./docs/ENGINEERING.md). The repository has strict agent-facing rules, including no comments in code and isolated unit tests that must not touch Docker or host files.

## License

MIT. See [LICENSE](./LICENSE).

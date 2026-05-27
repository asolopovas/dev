# Architecture

`web` is a Go CLI around Docker Compose. It keeps local PHP projects reproducible by deriving generated Caddy, SSL, cron, host-alias, and database state from a small host registry.

## Top-level flow

```text
web command
  -> Cobra command dispatch
  -> App methods validate inputs and mutate config
  -> Docker Compose runs services
  -> buildWebconf regenerates runtime files from web-hosts.json
```

`make install` builds the Go CLI and installs it to `/usr/local/bin/web`.

## Important paths

| Path | Purpose |
|---|---|
| `cmd/web`, `internal/web` | Go CLI, orchestration, host management, SSL, DB helpers |
| `docker-compose.yml` | Service definitions and local ports |
| `.env` | Compose environment values |
| `web-hosts.json` | Local host registry, gitignored |
| `franken_php/Dockerfile` | FrankenPHP runtime image |
| `franken_php/entrypoint.sh` | Dotfile hook, Supercronic startup, FrankenPHP/Caddy entrypoint |
| `franken_php/config/template.conf` | Per-host Caddy template |
| `launch.json` | Per-site VS Code debug template |
| `tests/` | Bats test suite |

## Docker services

| Service | Role |
|---|---|
| `franken_php` | Main Caddy + PHP 8.4 runtime; serves projects from `/var/www` |
| `mariadb` | Database server with root password from `.env` |
| `redis` | Redis with `redis/redis.conf` |
| `phpmyadmin` | FPM PhpMyAdmin mounted into a shared volume and served through Caddy |
| `mailpit` | Local SMTP sink and web UI |
| `typesense` | Local search service using `typesense-data/` |

`franken_php` is built from a multi-stage image. It copies FrankenPHP/PHP from `dunglas/frankenphp`, Composer from `composer:2`, installs PHP extensions and runtime libraries, adds Node.js, Bun, Fish, Supercronic, ripgrep, fd, fzf, and developer tooling, then runs as the configured non-root app user.

## Host registry

`web-hosts.json` is the source of truth for managed sites. It contains output paths, the Caddy template path, `WEB_ROOT`, the global `https` switch, and host entries with `name`, `type`, and `db`.

`build_webconf` initializes this file with defaults when it is missing. `new-host` writes through the JSON helpers and expects the registry to exist, so a fresh checkout should run `web build-webconf` once after services are started.

All JSON reads and writes should go through `LoadRegistry`, `EnsureRegistry`, and `SaveRegistry`. `SaveRegistry` writes to a temp file and moves it into place, keeping updates atomic.

## Generated files

`build_webconf` owns these outputs:

| Output | Source |
|---|---|
| `franken_php/config/sites/*.conf` | `franken_php/config/template.conf` plus each host entry |
| `franken_php/config/ssl/*.key`, `*.crt`, `*.csr` | local root CA and host certificate helpers when `https` is true |
| `templates.yml` | Docker Compose network aliases for managed hosts |
| `crontab` | WordPress cron entries for Supercronic |
| `<WEB_ROOT>/<host>/.vscode/launch.json` | `launch.json` template |

Generated files are not hand-maintained. Change the source templates or generation logic, then run `web build-webconf`.

## Host creation and removal

`new-host` validates Docker, parses the site type, computes a default database name when one is not supplied, scaffolds the project, appends to `web-hosts.json`, adds host redirection, rebuilds web config, and runs Laravel migrations for Laravel projects.

`remove-host` removes the database/user, project directory, host cert files, host redirection, and JSON entry. The interactive form can remove multiple selected hosts and then rebuilds config once.

## Database naming

`MakeDBName()` derives database names from hostnames:

- Known second-level domains include `co.uk`, `gov.uk`, `com.br`, and `co.jp`.
- Short second-level labels are treated as public suffix-like segments.
- WordPress hosts get `_wp`; other hosts get `_db`.
- Subdomains are included as suffixes on the main domain.
- Invalid identifier characters become `_`.
- Leading underscores are stripped; leading digits get a `db_` prefix.

Each host receives an isolated database and user with the same name.

## Local host mapping

Linux appends `127.0.0.1 <host>` to `/etc/hosts` through `sudo tee` and removes matching lines with `sudo sed`.

WSL is detected through `/proc/version`. WSL host mapping uses Windows PowerShell from WSL to update `C:\Windows\System32\drivers\etc\hosts` in one elevated process, so `rebuildWebConfiguration` should use batched host redirects instead of elevating once per host. The update handles a read-only Windows hosts file by temporarily clearing and then restoring the attribute.

## SSL

`rootssl` creates a local root CA under `franken_php/config/ssl/`. `hostssl <host>` creates a host key, CSR, and certificate signed by that root. `build_webconf` generates missing host certificates for redirect-only HTTPS blocks and full HTTPS site blocks. When `https` is false or missing, generated Caddy configs use those certificates only to redirect HTTPS requests back to HTTP.

`import-rootca` imports the root CA into the Linux NSS database used by Chrome/Brave. It is not supported on WSL.

## PHP configuration

Files under `franken_php/conf.d/` rely on PHP's native `${ENV_VAR}` interpolation. Compose passes Xdebug values from `.env`; PHP resolves them at startup. `web debug <mode>` edits `.env` and recreates `franken_php` so PHP reads the new mode.

Do not replace this with runtime edits to `.ini` files.

## Runtime entrypoint

`franken_php/entrypoint.sh` optionally runs `$HOME/dotfiles/scripts/ops-update-symlinks.sh`, discovers a non-empty crontab, starts Supercronic with passthrough logs, and then execs `docker-php-entrypoint` with the Caddyfile adapter.

# Operations

Use this to install, run, and maintain the local development stack.

## Install

Install requires Go, Docker, Docker Compose, Bash, `curl`, `tar`, and `openssl` for local redirect and HTTPS certificates.

```sh
mkdir -p "$HOME/www"
git clone https://github.com/asolopovas/dev.git "$HOME/www/dev"
cd "$HOME/www/dev"
cp .env.example .env
make install
```

The default paths assume the checkout lives at `$HOME/www/dev` and projects live under `$HOME/www`. For another layout, export `SCRIPT_DIR` and `WEB_ROOT` before running `web`.

`make install` builds the Go CLI and installs it as `/usr/local/bin/web`. If that path needs elevated permissions, the installer prompts through terminal `sudo` first, which works in WSL terminals, then falls back to non-interactive sudo and `SUDO_ASKPASS` or a detected askpass helper. It also installs shell completions under the current user's config directories, including configured host names for host commands, and updates an existing `$HOME/.local/bin/web` entry to point at `/usr/local/bin/web` so older installs do not shadow the Go binary.

If you skip installation, run commands as `go run ./cmd/web <command>` from the checkout directory with the same path assumptions or exported path variables.

## Configure

Edit `.env` before starting services.

| Variable | Default | Purpose |
|---|---|---|
| `MAPDIR` | `..` | Host directory mounted to `/var/www` |
| `APP_ENV` | `local` | App environment passed to PHP runtime |
| `APP_USER` | `www` | Container user name |
| `UID` / `GID` | `1000` | Container user/group IDs |
| `MYSQL_ROOT_PASSWORD` | `secret` | MariaDB root password |
| `REDIS_PASSWORD` | `redis` | Reserved; current Redis config does not require authentication |
| `WORKDIR` | `/var/www` | Container working directory |
| `XDEBUG_MODE` | `debug` | `off`, `debug`, or `profile` |
| `XDEBUG_IDEKEY` | `XDEBUG` | IDE key |
| `XDEBUG_TRIGGER` | `XDEBUG` | Trigger value |
| `XDEBUG_HOST` | `host.docker.internal` | Host address used by Xdebug |

The CLI defaults to `SCRIPT_DIR=$HOME/www/dev` and `WEB_ROOT=$HOME/www` unless those environment variables are overridden.

`web-hosts.json` contains the global HTTPS switch. Missing or false means HTTP mode:

```json
{
  "https": false,
  "hosts": []
}
```

Set `"https": true` only when you want HTTPS site blocks. HTTP mode still creates local certificates for redirect-only HTTPS blocks.

## First run

```sh
web up
web build-webconf
web new-host example.test -t wp
```

`web up` starts the services needed by host provisioning. `web build-webconf` initializes `web-hosts.json` when it is missing and regenerates baseline runtime files. Run it once before the first `new-host` in a fresh checkout.

## Start and stop

```sh
web up
web ps
web log franken_php
web restart franken_php
web stop
web down
```

`down` operates on the whole stack. Use `stop <service>` when you only want to stop one service. `up`, `build`, and `debug` remove stale Compose orphan containers so renamed services do not keep old ports bound.

## Build images

```sh
web build
web build franken_php
web build franken_php --no-cache
```

`web build` rebuilds images and recreates containers.

## Host lifecycle

Create WordPress:

```sh
web new-host example.test -t wp
```

Create Laravel:

```sh
web new-host api.test -t laravel
```

Run the interactive wizard:

```sh
web new-host
```

Remove one host:

```sh
web remove-host example.test
```

Remove hosts interactively:

```sh
web remove-host
```

Regenerate all generated runtime files:

```sh
web build-webconf
```

`build-webconf` reads `web-hosts.json`, adds local host mappings, creates missing certificates for redirect-only HTTPS blocks or full HTTPS site blocks, writes Caddy site files, writes Docker network aliases to `templates.yml`, writes WordPress cron lines to `crontab`, creates per-site VS Code launch configs, creates missing databases, and restarts `franken_php`.

## Scaffolding behavior

WordPress scaffolding downloads `latest-en_GB.tar.gz` into `WEB_ROOT` if needed, extracts it into the host directory, and fills `wp-config.php` with database values.

Laravel scaffolding runs `composer create-project --quiet --prefer-dist laravel/laravel`, updates `.env`, adds the host, rebuilds config, and runs `artisan migrate --force --quiet` through the `franken_php` container.

## SSL

HTTPS is off by default. In HTTP mode, generated Caddy config redirects `https://<host>` back to `http://<host>` using local redirect certificates and serves the site from HTTP. Browsers must trust the local root CA before they can follow an HTTPS redirect without a certificate warning.

Enable generated certificates globally:

```json
{
  "https": true
}
```

Then regenerate config:

```sh
web build-webconf
```

Generate the local root CA manually:

```sh
web rootssl
```

Generate a certificate for one host manually:

```sh
web hostssl example.test
```

Trust the root CA in Chrome/Brave on Linux:

```sh
web import-rootca
```

WSL users should trust certificates through Windows/browser tooling. `import-rootca` is Linux-only and exits on WSL.

## Database

Open MariaDB as root:

```sh
web mysql
```

Back up every database:

```sh
web db-backup
```

Restore from `db-backup.sql.gz`:

```sh
web db-restore
```

Managed hosts get a database and user named from the hostname. WordPress names end in `_wp`; Laravel and other site types end in `_db`.

## Redis

```sh
web redis-cli
web redis-flush
web redis-monitor
```

## Xdebug

```sh
web debug off
web debug debug
web debug profile
web debug
```

With no mode, `web debug` prompts in the terminal. The command edits `XDEBUG_MODE` in `.env` and recreates `franken_php`.

IDE defaults:

- Client port: `9003`
- IDE key: `XDEBUG`
- Host: `host.docker.internal`

## Shell access

```sh
web bash
web fish
web dir
```

`dir` prints the script directory.

## Services

| Service | Image | Ports |
|---|---|---|
| `franken_php` | `asolopovas/franken-php:latest`, built from `franken_php/Dockerfile` | 80, 443, 443/udp, 8080, 3000/udp, 3001/udp |
| `mariadb` | `mariadb:lts` | 3306 |
| `redis` | `redis:7.4.2-bookworm` | 6379 |
| `phpmyadmin` | `phpmyadmin/phpmyadmin:fpm-alpine` | served at `phpmyadmin.test` |
| `mailpit` | `axllent/mailpit:latest` | 1025 SMTP, 8025 UI |
| `typesense` | `typesense/typesense:29.0` | 8108 |

## WSL notes

Host redirection on WSL uses Windows PowerShell to update `C:\Windows\System32\drivers\etc\hosts`. `build-webconf` batches mappings into one elevated PowerShell run, so expect one UAC prompt for many hosts. If the Windows hosts file is read-only, the CLI clears the attribute for the update and restores it afterward.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Port 80 or 443 is already in use | Stop host-level nginx/apache/Caddy, run `web up` to remove old project orphans, or change the compose port mappings |
| `web` command not found | Run `make install` and ensure `/usr/local/bin` is on `PATH` |
| WSL hosts file did not update | Accept the UAC prompt from Windows PowerShell |
| Browser does not trust HTTPS | Run `web rootssl`, `web import-rootca`, then restart Chrome/Brave |
| Xdebug does not connect | Confirm the IDE listens on 9003, `XDEBUG_HOST=host.docker.internal`, and `XDEBUG_IDEKEY=XDEBUG` |
| Laravel scaffold fails before Docker commands | Install Composer on the host |
| Generated Caddy config is stale | Run `web build-webconf` |

# Web.sh - PHP Development Environment

`web.sh` is a powerful and developer-friendly shell utility designed to streamline local development of PHP applications using Docker. It offers built-in support for **WordPress**, **Laravel**, and more, with automatic setup of SSL certificates, host redirection, Docker services, and supervisor configuration — all from a single command-line tool.

---

## Features

* **Dockerized environment** for PHP 8.3, MariaDB, Redis, Caddy, PhpMyAdmin, Mailhog, and Typesense
* **Quick WordPress/Laravel setup** with SSL and database
* **Automatic root and site-specific SSL certificate generation**
* **HTTP/3 (QUIC) support** via Caddy
* **Local domain redirection** (`/etc/hosts` or Windows/WSL compatible)
* **Fish shell** completions and environment
* **Supervisor** support for Laravel Horizon
* **Chrome Root CA import** support
* JSON-based host configuration (`web-hosts.json`)
* **Node.js via Volta** with npm and Bun pre-installed
* **Xdebug** with VSCode integration
* Developer-focused tools and utilities built-in

---

## Directory Structure

```text
.
├── web.sh                         # Main CLI utility
├── docker-compose.yml             # Docker service definitions
├── web-hosts.json                 # Host definitions
├── templates.yml                  # Auto-generated Docker network aliases
├── crontab                        # Auto-generated WordPress cron jobs
├── .env                           # Environment variables
├── launch.json                    # VSCode Xdebug configuration template
├── logs/                          # Application logs directory
├── db/                            # Database utilities
│   └── template.txt               # DB template file
├── franken_php/                   # PHP service configuration
│   ├── Dockerfile                 # PHP 8.3 container build
│   ├── entrypoint.sh              # Container startup script
│   ├── conf.d/                    # PHP configuration files
│   │   ├── error-logging.ini
│   │   ├── opcache.ini
│   │   ├── sessions.ini
│   │   ├── upload.ini
│   │   └── xdebug.ini
│   ├── config/                    # Caddy configuration
│   │   ├── Caddyfile              # Main Caddy config
│   │   ├── cors.conf              # CORS settings for WordPress
│   │   ├── template.conf          # Site config template
│   │   ├── sites/                 # Per-host Caddy configs (auto-generated)
│   │   └── ssl/                   # SSL certificates and keys
│   └── other_config/              # Additional configurations
│       ├── messenger-worker.conf  # Symfony Messenger template
│       └── msmtprc                # Mailhog SMTP config
├── mariadb/                       # MariaDB service
│   ├── Dockerfile
│   └── custom.cnf                 # Custom MySQL settings
├── redis/                         # Redis service
│   ├── Dockerfile
│   └── redis.conf                 # Redis configuration
└── typesense-data/                # Typesense search engine data
```

---

## Installation

```sh
web install
```

This creates symlinks:

* `~/.local/bin/web` → CLI utility
* `~/.config/fish/completions/web.fish` → Fish shell completion

---

## Usage Overview

Run the following to see all available options:

```sh
web
```

### Add a New Host

```sh
web new-host example.test -t wp        # WordPress
web new-host project.local -t laravel  # Laravel
```

This will:

* Download and install the framework
* Generate SSL certificates
* Add host entries
* Create and configure databases
* Build Caddy configs and restart services

---

## Commands Reference

### Environment Management

| Command                            | Description                              |
| ---------------------------------- | ---------------------------------------- |
| `web up [service]`                 | Start all or specified Docker services   |
| `web down`                         | Stop and remove all Docker services      |
| `web stop [service]`               | Stop all or specified Docker services    |
| `web restart [service]`            | Restart all or specified Docker services |
| `web build [service] [--no-cache]` | Build all or specified Docker services   |
| `web ps [service]`                 | Show Docker container status             |
| `web log <service>`               | View logs for a Docker service           |

### Host Management

| Command                                    | Description                                  |
| ------------------------------------------ | -------------------------------------------- |
| `web new-host <hostname> -t <wp\|laravel>` | Create new WordPress or Laravel site         |
| `web remove-host <hostname>`               | Remove site, DB, SSL, and host redirection   |
| `web build-webconf`                        | Regenerate Caddy configs from web-hosts.json |

### Shell Access

| Command    | Description                   |
| ---------- | ----------------------------- |
| `web bash` | Access container's Bash shell |
| `web fish` | Access container's Fish shell |

### SSL Management

| Command              | Description                                  |
| -------------------- | -------------------------------------------- |
| `web rootssl`        | Generate root CA certificate                 |
| `web hostssl <host>` | Generate SSL certificate for a specific host |
| `web import-rootca`  | Import root CA to Chrome (Linux only)        |

### Database & Caching

| Command             | Description            |
| ------------------- | ---------------------- |
| `web redis-flush`   | Flush Redis cache      |
| `web redis-monitor` | Monitor Redis activity |

### Debugging

| Command             | Description             |
| ------------------- | ----------------------- |
| `web debug off`     | Disable Xdebug          |
| `web debug debug`   | Enable Xdebug debugging |
| `web debug profile` | Enable Xdebug profiling |

### Supervisor (Laravel Horizon)

| Command                      | Description                                    |
| ---------------------------- | ---------------------------------------------- |
| `web supervisor-conf <host>` | Generate Supervisor config for Laravel Horizon |
| `web supervisor-restart`     | Restart Supervisor service                     |

### Utilities

| Command                                  | Description                                  |
| ---------------------------------------- | -------------------------------------------- |
| `web install`                            | Create symlinks for CLI and Fish completions |
| `web dir`                                | Output the script directory path             |
| `web git-update <user> <theme> [plugin]` | Update theme/plugin via git on lyntouch.com  |

---

## SSL & Security

* Root CA is generated via `web rootssl`
* Host SSL certificates are issued with `web hostssl <host>`
* SSL certs are stored in: `franken_php/config/ssl`
* Use `web import-rootca` to trust the CA in **Chrome/Linux** environments

---

## Removing a Host

```sh
web remove-host example.test
```

This will:

* Remove project files
* Drop database and user
* Remove SSL certs and redirect entry
* Regenerate Caddy configs

---

## Docker Services

| Service         | Description                                | Ports                            |
| --------------- | ------------------------------------------ | -------------------------------- |
| **franken_php** | PHP 8.3 + Caddy web server with Xdebug    | 80, 443, 443/udp (HTTP/3), 8080 |
| **mariadb**     | MariaDB database server (MySQL compatible) | 3306                             |
| **redis**       | Redis caching server                       | 6379                             |
| **phpmyadmin**  | Database management GUI                    | via Caddy                        |
| **mailhog**     | Email testing service                      | 1025 (SMTP), 8025 (Web UI)      |
| **typesense**   | Search engine                              | 8108                             |

---

## PHP Extensions

The PHP container includes the following extensions:

**Core:** bcmath, calendar, exif, mbstring, mysqli, pdo, pdo_mysql, pdo_pgsql, pdo_sqlite, pcntl, xml, zip, intl, gd (with freetype, jpeg, avif, webp)

**PECL:** imagick, xdebug, redis, apcu, igbinary

---

## Pre-installed Tools

The container comes with the following tools:

* **Composer** - PHP dependency manager
* **Node.js** (via Volta) - JavaScript runtime with npm and Bun
* **wkhtmltopdf** - PDF generation
* **ffmpeg** - Video/audio processing
* **fd** and **fzf** - File finding utilities
* **msmtp** - Pre-configured to use Mailhog for email

---

## Environment Variables

Key variables in `.env`:

| Variable              | Description                   | Default          |
| --------------------- | ----------------------------- | ---------------- |
| `MAPDIR`              | Maps to parent directory      | `..`             |
| `APP_ENV`             | Application environment       | `local`          |
| `APP_USER`            | Container user                | `www`            |
| `UID` / `GID`         | User/Group ID for permissions | `1000`           |
| `MYSQL_ROOT_PASSWORD` | Database root password        | `secret`         |
| `XDEBUG_MODE`        | Xdebug behavior               | `off`            |
| `XDEBUG_IDEKEY`      | IDE key for debugging         | `XDEBUG_ECLIPSE` |
| `NODE_VERSION`        | Node.js version for container | `22.16.0`        |

---

## Xdebug Integration

The environment includes VSCode Xdebug configuration. Copy `launch.json` to your `.vscode` folder:

```sh
cp launch.json .vscode/launch.json
```

Enable debugging:

```sh
web debug debug     # Enable
web debug off       # Disable
web debug profile   # Enable profiling
```

---

## CORS Configuration

WordPress REST API CORS is pre-configured in `franken_php/config/cors.conf` to allow requests from `localhost:3000` for frontend development.

---

## WSL/Windows Support

Host file management is supported on Windows/WSL through PowerShell integration. The script automatically detects the environment and uses appropriate methods for host redirection.

---

## Fish Shell Completions

Full CLI autocompletion support is available for Fish shell:

```sh
web install  # Installs completions
```

---

## Requirements

* Docker & Docker Compose
* Fish shell (optional, for autocompletions)
* jq, curl, tar, openssl, sed, and common UNIX tools

---

## Credits

Created with care at [Lyntouch](https://lyntouch.com). Inspired by modern PHP workflows.

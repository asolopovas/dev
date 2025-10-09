# 🛠️ Web.sh — A Powerful PHP Development Environment

`web.sh` is a powerful and developer-friendly shell utility designed to streamline local development of PHP applications using Docker. It offers built-in support for **WordPress**, **Laravel**, and more, with automatic setup of SSL certificates, host redirection, Docker services, and supervisor configuration — all from a single command-line tool.

---

## 🚀 Features

* 📦 **Dockerized environment** for PHP, MariaDB, Redis, Caddy, PhpMyAdmin, and Mailhog
* ⚡ **Quick WordPress/Laravel setup** with SSL and database
* 🛡️ **Automatic root and site-specific SSL certificate generation**
* 🌐 **Local domain redirection** (`/etc/hosts` or Windows-compatible)
* 🐠 **Fish shell** completions and environment
* 🔧 **Supervisor** support for Laravel Horizon
* 📥 **Chrome Root CA import** support
* 📚 JSON-based host configuration (`web-hosts.json`)
* 🛠️ Developer-focused tools and utilities built-in

---

## 📁 Directory Structure

```text
.
├── web.sh                         # Main CLI utility
├── docker-compose.yml             # Services for development
├── franken_php/                   # PHP service configs (Caddy, templates, etc.)
│   ├── config/
│   │   ├── sites/                 # Per-host Caddy configs
│   │   └── ssl/                   # SSL certs and keys
├── mariadb/                       # MariaDB Docker build context
├── redis/                         # Redis Docker build context
├── templates.yml                  # Auto-generated service aliases
└── web-hosts.json                 # Host definitions
```

---

## ⚙️ Installation

```sh
web install
```

This creates symlinks:

* `~/.local/bin/web` → CLI utility
* `~/.config/fish/completions/web.fish` → Fish shell completion

---

## 📌 Usage Overview

Run the following to see all available options:

```sh
web
```

### 🆕 Add a New Host

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

## 🧰 Common Commands

| Command                                 | Description                          |            |                 |
| --------------------------------------- | ------------------------------------ | ---------- | --------------- |
| `web bash`                              | Access app container's Bash          |            |                 |
| `web fish`                              | Access app container's Fish shell    |            |                 |
| `web build`                             | Rebuild all Docker services          |            |                 |
| `web build app`                         | Rebuild only the app container       |            |                 |
| `web build-webconf`                     | Regenerate Caddy configs             |            |                 |
| `web rootssl`                           | Create root CA SSL                   |            |                 |
| `web hostssl <host>`                    | Generate SSL for a specific host     |            |                 |
| `web ps`                                | Show Docker container statuses       |            |                 |
| `web up` / `web down`                   | Start/stop Docker services           |            |                 |
| `web log <service>`                     | Tail logs from a specific service    |            |                 |
| `web remove-host <host>`                | Remove site + DB + SSL + redirection |            |                 |
| \`web debug \<off                       | debug                                | profile>\` | Set Xdebug mode |
| `web redis-flush` / `web redis-monitor` | Redis utilities                      |            |                 |

---

## 🔐 SSL & Security

* Root CA is generated via `web rootssl`
* Host SSL certificates are issued with `web hostssl <host>`
* SSL certs are stored in: `php/config/ssl`
* Use `web import-rootca` to trust the CA in **Chrome/Linux** environments

---

## 🛑 Removing a Host

```sh
web remove-host example.test
```

This will:

* Remove project files
* Drop database and user
* Remove SSL certs and redirect entry
* Regenerate Caddy configs

---

## 🔍 Advanced

### 🧪 Enable Xdebug

```sh
web debug debug     # Enable
web debug off       # Disable
```

### 📡 Supervisor for Laravel Horizon

```sh
web supervisor-conf mysite.test
web restart-supervisor
```

---

## 🐳 Services via Docker Compose

* `franken_php`: Custom PHP environment with Caddy
* `mariadb`: MariaDB for MySQL compatibility
* `redis`: Redis caching server
* `phpmyadmin`: GUI for managing DB
* `mailhog`: Catch all outgoing emails during development

---

## 🐚 Fish Shell Completions

Enjoy full CLI autocompletion support with:

```sh
web fish
```

---

## ✅ Requirements
* Docker & Docker Compose
* Fish shell (optional, for autocompletions)
* jq, curl, tar, openssl, sed, and common UNIX tools

---

## 👏 Credits

Created with ❤️ at [Lyntouch](https://lyntouch.com). Inspired by modern PHP workflows.


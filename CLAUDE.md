# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **web.sh** - a powerful Docker-based PHP development environment that streamlines local development of WordPress and Laravel applications. The system provides automated SSL certificate generation, host redirection, database management, and Supervisor configuration through a single command-line utility.

## Core Architecture

The project uses Docker Compose to orchestrate multiple services:
- **franken_php**: Custom PHP environment with FrankenPHP (Caddy + PHP) 
- **mariadb**: Database service with MySQL compatibility
- **redis**: Caching server
- **phpmyadmin**: Database management GUI
- **mailhog**: Email testing service

Host configurations are managed through `web-hosts.json`, which defines site names, types (WordPress/Laravel), and database associations. The system automatically generates Caddy server configs, SSL certificates, and host redirections.

## Essential Commands

### Environment Management
```bash
./web.sh up                    # Start all Docker services
./web.sh down                  # Stop and remove all services
./web.sh build                 # Rebuild all Docker images
./web.sh build app             # Rebuild only the franken_php service
./web.sh restart               # Restart all services
./web.sh ps                    # Show container status
```

### Host Management
```bash
./web.sh new-host example.test -t wp       # Create new WordPress site
./web.sh new-host api.test -t laravel      # Create new Laravel project
./web.sh remove-host example.test          # Remove site completely
./web.sh build-webconf                     # Regenerate Caddy configs
```

### Development Tools
```bash
./web.sh bash                  # Access container bash shell
./web.sh fish                  # Access container fish shell
./web.sh log <service>         # View service logs
./web.sh debug debug           # Enable Xdebug
./web.sh debug off             # Disable Xdebug
```

### SSL Management
```bash
./web.sh rootssl               # Generate root CA certificate
./web.sh hostssl <hostname>    # Generate SSL for specific host
./web.sh import-rootca         # Import root CA to Chrome (Linux only)
```

### Database Operations
```bash
./web.sh redis-flush           # Clear Redis cache
./web.sh redis-monitor         # Monitor Redis activity
```

## Project Structure

- `web.sh` - Main CLI utility with all functionality
- `docker-compose.yml` - Service definitions
- `web-hosts.json` - Host configuration database
- `franken_php/` - PHP service configuration
  - `config/sites/` - Per-host Caddy configs (auto-generated)
  - `config/ssl/` - SSL certificates and keys
  - `config/template.conf` - Caddy config template
- `mariadb/` - Database service build context
- `redis/` - Redis service build context

## Development Workflow

1. **Initial Setup**: Run `./web.sh install` to create symlinks
2. **Add New Sites**: Use `./web.sh new-host <hostname> -t <type>`
3. **SSL Setup**: Root CA is auto-generated, host certificates created per site
4. **Database Access**: Each site gets its own database and user
5. **Configuration**: Modify `web-hosts.json` for manual host management

## Important Files

- `.env` - Environment variables for Docker services
- `web-hosts.json` - Centralized host configuration
- `crontab` - Auto-generated WordPress cron jobs
- `templates.yml` - Auto-generated service aliases

## Key Features

- Automatic SSL certificate generation with custom root CA
- Host redirection management (`/etc/hosts` or Windows hosts file)
- Database isolation per project with auto-provisioning
- WordPress and Laravel project scaffolding
- Supervisor integration for Laravel Horizon
- Fish shell completions and environment
- Xdebug integration with IDE support

## Environment Variables

Key variables in `.env`:
- `MAPDIR` - Maps to parent directory (`..`)
- `XDEBUG_MODE` - Controls Xdebug behavior (off/debug/profile)
- `MYSQL_ROOT_PASSWORD=secret` - Database root password
- `NODE_VERSION` - Node.js version for container builds
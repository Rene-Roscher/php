# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Production-ready PHP Docker images (8.2, 8.3, 8.4) optimized for Laravel applications. Single universal image per PHP version - fully configurable via 100+ ENV variables.

**Repository:** `git@github.com:Rene-Roscher/php.git`

## Architecture

### Universal Image Design
- **One image per PHP version** (not multiple profiles)
- **Runtime configuration** via ENV variables
- **Flexible socket support:** Unix Socket (default) OR TCP Socket
- **Multi-arch:** AMD64 + ARM64

### Components
- **Base:** PHP-FPM on Alpine Linux
- **Web Server:** Nginx
- **Process Manager:** S6-Overlay v3
- **Cron:** For Laravel scheduler
- **Optional:** Certbot for SSL

### Socket Configuration
**Auto-detection based on `FPM_LISTEN` ENV:**
- Unix Socket: `FPM_LISTEN=/run/php/php-fpm.sock` (default, ~10-15% faster)
- TCP Socket: `FPM_LISTEN=127.0.0.1:9000` (debugging/legacy)

Nginx configuration automatically adjusts to match FPM socket type.

## Key Files

### Dockerfile
- Multi-stage build (base → runtime → final)
- **IMPORTANT:** Removes default `/usr/local/etc/php-fpm.d/www.conf` to avoid conflicts
- Installs: `gettext` for envsubst, `fcgi` for health checks
- S6-Overlay downloaded and extracted during build

### Runtime Configuration Scripts
**Location:** `/rootfs/etc/cont-init.d/`

**CRITICAL:** All scripts MUST use `#!/usr/bin/with-contenv bash` shebang for ENV visibility!

1. **01-setup-configs.sh** - Generates PHP/FPM/Nginx configs from ENV
2. **02-laravel-setup.sh** - Laravel optimizations (artisan optimize, etc.)
3. **03-certbot-setup.sh** - SSL certificate management
4. **04-cron-setup.sh** - Cron setup for Laravel scheduler

### Templates
**Location:** `/rootfs/etc/templates/`

- `nginx-laravel.conf` - Laravel-optimized Nginx config with FastCGI optimizations

Variables substituted via `envsubst`: `${NGINX_WEBROOT}`, `${FPM_PASS}`, `${APP_ENV}`, etc.

## Configuration System

### Socket Detection Logic (01-setup-configs.sh)
```bash
# Runs FIRST before any config generation
FPM_LISTEN_VALUE="${FPM_LISTEN:-/run/php/php-fpm.sock}"

if [[ "${FPM_LISTEN_VALUE}" == *":"* ]]; then
    # TCP Socket
    export FPM_PASS="${FPM_LISTEN_VALUE}"
    IS_UNIX_SOCKET=0
else
    # Unix Socket
    export FPM_PASS="unix:${FPM_LISTEN_VALUE}"
    IS_UNIX_SOCKET=1
fi
```

### PHP-FPM Config Generation
- Creates `/usr/local/etc/php-fpm.d/zz-runtime.conf`
- Sets `listen = ${FPM_LISTEN_VALUE}`
- If Unix socket: adds owner/group/mode directives
- If TCP socket: skips socket permissions

### Nginx Config Generation
- Runtime config: `/etc/nginx/http.d/99-runtime.conf` (buffers, timeouts)
- Server config: `/etc/nginx/http.d/default.conf` (from template)
- Uses `envsubst` to replace `${FPM_PASS}` with correct socket path

## Laravel Optimizations

### OPcache Configuration
- **JIT Compiler:** Enabled by default (`tracing` mode)
- **Memory:** 256MB default (configurable via `OPCACHE_MEMORY_CONSUMPTION`)
- **Validate Timestamps:**
  - Production: `0` (no file checks, max performance)
  - Development: `1` (auto-reload on code changes)

### Nginx FastCGI
- **Buffers:** 8x16k (handles large Laravel responses)
- **Timeouts:** 60s default
- **Static Assets:** 1-year cache for images/css/js

### Realpath Cache
- **Size:** 4096k (critical for Laravel's many file includes)
- **TTL:** 600s

## Environment Variables

### Critical Variables
- `FPM_LISTEN` - Socket type (Unix or TCP)
- `NGINX_WEBROOT` - Document root (default: `/var/www/public`)
- `APP_ENV` - Laravel environment
- `OPCACHE_VALIDATE_TIMESTAMPS` - Code reloading (0=production, 1=dev)
- `LARAVEL_OPTIMIZE_ON_BOOT` - Run artisan optimize on startup

### Performance Tuning
- `FPM_PM_TYPE` - static/dynamic/ondemand
- `FPM_PM_MAX_CHILDREN` - Worker count
- `OPCACHE_MEMORY_CONSUMPTION` - OPcache size
- `OPCACHE_JIT_BUFFER_SIZE` - JIT buffer size

See `.env.example` for complete list (100+ variables).

## CI/CD

### GitHub Actions
**Workflow:** `.github/workflows/build-multivariant.yml`

Builds 3 universal images:
- `ghcr.io/rene-roscher/php:8.2`
- `ghcr.io/rene-roscher/php:8.3`
- `ghcr.io/rene-roscher/php:latest` (8.3)
- `ghcr.io/rene-roscher/php:8.4`

**Platforms:** `linux/amd64,linux/arm64`

### Tags Strategy
- Version: `8.3`, `8.2`, `8.4`
- Latest: `latest` (only PHP 8.3 on main branch)
- SHA: `8.3-{{sha}}`
- Branch: `branch-name-8.3`

## Common Issues & Solutions

### Issue: ENV Variables Not Visible in Init Scripts
**Symptom:** `FPM_LISTEN` is set but script uses default value
**Cause:** Script uses `#!/bin/bash` instead of `#!/usr/bin/with-contenv bash`
**Fix:** Always use `#!/usr/bin/with-contenv bash` for S6-Overlay compatibility

### Issue: Socket Permission Denied
**Symptom:** Nginx can't connect to FPM Unix socket
**Cause:** Nginx user not in www-data group
**Fix:** Already handled - `addgroup nginx www-data` in Dockerfile

### Issue: Nginx Shows 404 After Container Start
**Symptom:** Nginx config not loaded, shows default 404
**Cause:** Nginx starts before config is generated
**Workaround:** `docker exec <container> nginx -s reload`
**TODO:** Fix S6 service dependencies

### Issue: OPcache Not Updating Code
**Symptom:** Code changes not reflected
**Cause:** `OPCACHE_VALIDATE_TIMESTAMPS=0` (production mode)
**Fix:** Set `OPCACHE_VALIDATE_TIMESTAMPS=1` for development

## Testing

### Quick Test
```bash
docker run -d -p 8080:80 \
  -v $(pwd)/test-app:/var/www \
  -e FPM_LISTEN=/run/php/php-fpm.sock \
  -e NGINX_WEBROOT=/var/www/public \
  ghcr.io/rene-roscher/php:8.3

curl http://localhost:8080/
```

### Verify Socket Type
```bash
docker logs <container> | grep "Using"
# Output: [Init] Using Unix socket: unix:/run/php/php-fpm.sock
# Or:     [Init] Using TCP socket: 127.0.0.1:9000
```

### Check Configs
```bash
# FPM listen config
docker exec <container> grep "^listen" /usr/local/etc/php-fpm.d/zz-runtime.conf

# Nginx FPM pass
docker exec <container> grep "fastcgi_pass" /etc/nginx/http.d/default.conf
```

## Development Workflow

### Local Build
```bash
docker build --build-arg PHP_VERSION=8.3 --build-arg ALPINE_VERSION=3.19 -t php-local:8.3 .
```

### Test Different Configurations
```bash
# Unix Socket (default)
docker run -d -p 8090:80 -v $(pwd)/test-app:/var/www \
  -e FPM_LISTEN=/run/php/php-fpm.sock \
  php-local:8.3

# TCP Socket
docker run -d -p 8091:80 -v $(pwd)/test-app:/var/www \
  -e FPM_LISTEN=127.0.0.1:9000 \
  php-local:8.3
```

### Add New ENV Variable
1. Add to `01-setup-configs.sh` with default value: `${NEW_VAR:-default}`
2. Document in `.env.example`
3. Update CLAUDE.md if it's critical
4. Test with docker run

## Production Deployment

### Recommended Settings (8GB+ Server)
```yaml
environment:
  FPM_LISTEN: /run/php/php-fpm.sock
  FPM_PM_TYPE: static
  FPM_PM_MAX_CHILDREN: 200
  PHP_MEMORY_LIMIT: 512M
  OPCACHE_MEMORY_CONSUMPTION: 512
  OPCACHE_VALIDATE_TIMESTAMPS: "0"
  OPCACHE_JIT_BUFFER_SIZE: 200M
```

### Small Server (512MB-1GB)
```yaml
environment:
  FPM_LISTEN: /run/php/php-fpm.sock
  FPM_PM_TYPE: dynamic
  FPM_PM_MAX_CHILDREN: 8
  FPM_PM_START_SERVERS: 2
  PHP_MEMORY_LIMIT: 128M
  OPCACHE_MEMORY_CONSUMPTION: 128
```

## Important Notes

- **No Profile Images:** We build ONE universal image per PHP version
- **S6-Overlay:** Handles process management (not Supervisor)
- **Init Script Order:** 01 → 02 → 03 → 04 (numbered)
- **Nginx Reload:** May need manual reload after first start (known issue)
- **Socket Performance:** Unix ~10-15% faster than TCP (only noticeable at high load)

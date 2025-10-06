# Laravel PHP Docker - Universal Image

Production-ready PHP Docker image optimized for Laravel. Single universal image per PHP version - configure everything via ENV variables at runtime.

[![Build Status](https://github.com/Rene-Roscher/php/workflows/Build%20Multi-Variant%20Docker%20Images/badge.svg)](https://github.com/Rene-Roscher/php/actions)

## Features

- **Universal Image Design** - One image per PHP version, configure via 100+ ENV variables
- **PHP Versions** - 8.2, 8.3, 8.4 (multi-arch: AMD64 + ARM64)
- **Socket Flexibility** - Unix socket (default) or TCP socket via ENV
- **S6-Overlay** - Modern process supervision
- **Laravel Optimized** - OPcache JIT, realpath cache, auto-optimization
- **SSL/Certbot** - Automatic certificate management
- **Production Ready** - Security hardened, performance optimized

## Quick Start

```bash
# Pull image (PHP 8.3)
docker pull ghcr.io/rene-roscher/php:8.3

# Run with default settings
docker run -d -p 80:80 -v $(pwd):/var/www ghcr.io/rene-roscher/php:8.3
```

## Available Tags

| Tag | PHP Version | Platforms |
|-----|-------------|-----------|
| `latest` | 8.3 | amd64, arm64 |
| `8.2` | 8.2 | amd64, arm64 |
| `8.3` | 8.3 | amd64, arm64 |
| `8.4` | 8.4 | amd64, arm64 |

## Docker Compose Examples

### Development

```yaml
services:
  app:
    image: ghcr.io/rene-roscher/php:8.3
    ports:
      - "8000:80"
    volumes:
      - ./:/var/www
    environment:
      APP_ENV: local
      APP_DEBUG: "true"

      # Socket (Unix = default)
      FPM_LISTEN: /run/php/php-fpm.sock

      # Development-friendly OPcache
      OPCACHE_VALIDATE_TIMESTAMPS: "1"

      # No Laravel optimization in dev
      LARAVEL_OPTIMIZE_ON_BOOT: "false"
```

### Production

```yaml
services:
  app:
    image: ghcr.io/rene-roscher/php:8.3
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./:/var/www
      - certbot-data:/etc/letsencrypt
    environment:
      APP_ENV: production
      APP_DEBUG: "false"

      # Database
      DB_HOST: mysql
      DB_DATABASE: laravel

      # Socket Configuration (Unix = best performance)
      FPM_LISTEN: /run/php/php-fpm.sock

      # PHP Settings
      PHP_MEMORY_LIMIT: 512M

      # FPM Pool (adapt to your server!)
      FPM_PM_TYPE: dynamic
      FPM_PM_MAX_CHILDREN: 50

      # OPcache (maximum performance)
      OPCACHE_VALIDATE_TIMESTAMPS: "0"
      OPCACHE_JIT: tracing
      OPCACHE_JIT_BUFFER_SIZE: 200M

      # SSL
      CERTBOT_ENABLED: "true"
      CERTBOT_DOMAINS: example.com
      CERTBOT_EMAIL: admin@example.com

      # Laravel
      LARAVEL_OPTIMIZE_ON_BOOT: "true"

    healthcheck:
      test: ["CMD", "/usr/local/bin/healthcheck.sh"]
      interval: 30s
      timeout: 3s
      retries: 3

    restart: unless-stopped

volumes:
  certbot-data:
```

## Configuration Presets

Configure the **same image** for different server sizes via ENV:

### Small Server (512MB-1GB RAM)

```yaml
environment:
  FPM_LISTEN: /run/php/php-fpm.sock
  FPM_PM_TYPE: dynamic
  FPM_PM_MAX_CHILDREN: 8
  PHP_MEMORY_LIMIT: 128M
  OPCACHE_MEMORY_CONSUMPTION: 128
```

### Medium Server (2-4GB RAM)

```yaml
environment:
  FPM_LISTEN: /run/php/php-fpm.sock
  FPM_PM_TYPE: dynamic
  FPM_PM_MAX_CHILDREN: 50
  PHP_MEMORY_LIMIT: 256M
  OPCACHE_MEMORY_CONSUMPTION: 256
```

### Large Server (8GB+ RAM)

```yaml
environment:
  FPM_LISTEN: /run/php/php-fpm.sock
  FPM_PM_TYPE: static
  FPM_PM_MAX_CHILDREN: 200
  PHP_MEMORY_LIMIT: 512M
  OPCACHE_MEMORY_CONSUMPTION: 512
  OPCACHE_JIT: tracing
  OPCACHE_JIT_BUFFER_SIZE: 200M
```

## Socket Configuration

The image auto-detects socket type from `FPM_LISTEN` ENV:

```yaml
# Unix Socket (default - best performance)
FPM_LISTEN: /run/php/php-fpm.sock

# TCP Socket (for multi-container setups)
FPM_LISTEN: 127.0.0.1:9000
```

## Key Environment Variables

### PHP Core
```bash
PHP_MEMORY_LIMIT=256M
PHP_MAX_EXECUTION_TIME=60
PHP_UPLOAD_MAX_FILESIZE=200M
PHP_POST_MAX_SIZE=200M
```

### FPM Pool
```bash
FPM_LISTEN=/run/php/php-fpm.sock   # or 127.0.0.1:9000
FPM_PM_TYPE=dynamic                 # static|dynamic|ondemand
FPM_PM_MAX_CHILDREN=50
FPM_PM_START_SERVERS=10
```

### OPcache
```bash
OPCACHE_ENABLE=1
OPCACHE_MEMORY_CONSUMPTION=256
OPCACHE_MAX_ACCELERATED_FILES=20000
OPCACHE_VALIDATE_TIMESTAMPS=0       # 0=production, 1=development
OPCACHE_JIT=tracing                 # PHP 8.0+ JIT compiler
OPCACHE_JIT_BUFFER_SIZE=100M
```

### Nginx
```bash
NGINX_WEBROOT=/var/www/public
NGINX_WORKER_CONNECTIONS=2048
NGINX_CLIENT_MAX_BODY_SIZE=200M
```

### SSL/Certbot
```bash
CERTBOT_ENABLED=true
CERTBOT_EMAIL=admin@example.com
CERTBOT_DOMAINS=example.com,www.example.com
CERTBOT_AUTO_RENEW=true
```

### Laravel
```bash
LARAVEL_OPTIMIZE_ON_BOOT=true
LARAVEL_SCHEDULE_ENABLED=true
AUTORUN_LARAVEL_STORAGE_LINK=false
AUTORUN_LARAVEL_MIGRATION=false
```

**See [`.env.example`](.env.example) for complete list of 100+ variables.**

## Queue Workers

Use the same image with different command:

```yaml
services:
  # Web server
  app:
    image: ghcr.io/rene-roscher/php:8.3
    ports: ["80:80"]
    volumes: ["./:/var/www"]
    environment:
      APP_ENV: production

  # Queue worker (separate container)
  queue:
    image: ghcr.io/rene-roscher/php:8.3
    command: php artisan queue:work --tries=3
    volumes: ["./:/var/www"]
    environment:
      APP_ENV: production
      PHP_MEMORY_LIMIT: 256M

  # Horizon (if you use it)
  horizon:
    image: ghcr.io/rene-roscher/php:8.3
    command: php artisan horizon
    volumes: ["./:/var/www"]
    environment:
      APP_ENV: production
```

## Health Checks

The image includes comprehensive health checks:

| Endpoint | Purpose |
|----------|---------|
| `/health` | Application health |
| `/ping` | PHP-FPM ping |
| `/status` | PHP-FPM status |

```bash
# Check container health
docker inspect --format='{{.State.Health.Status}}' <container>

# Manual health check
docker exec <container> /usr/local/bin/healthcheck.sh
```

## Performance Tuning

### Calculate FPM max_children

```bash
# Formula: (Total RAM - System) / PHP Memory per Process
# Example: (4GB - 1GB) / 64MB = ~46 processes

FPM_PM_MAX_CHILDREN=46
FPM_PM_START_SERVERS=12
```

### Monitor Performance

```bash
# FPM status
curl http://localhost/status?full

# OPcache stats
docker exec <container> php -r "print_r(opcache_get_status());"

# Watch processes
docker exec <container> watch 'ps aux | grep php-fpm'
```

## Building Custom Images

```dockerfile
FROM ghcr.io/rene-roscher/php:8.3

# Install additional extensions
COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/
RUN install-php-extensions mongodb grpc

# Copy application
COPY . /var/www
```

## Debugging

```bash
# Enable debug mode
environment:
  APP_DEBUG: "true"
  PHP_DISPLAY_ERRORS: "On"
  OPCACHE_VALIDATE_TIMESTAMPS: "1"
  LOG_LEVEL: debug

# View logs
docker logs -f <container>

# Shell access
docker exec -it <container> bash
```

## Makefile Commands

```bash
make build          # Build image
make test           # Run tests
make dev            # Start development environment
make prod           # Start production environment
make help           # Show all commands
```

## Links

- **Repository:** https://github.com/Rene-Roscher/php
- **Registry:** https://ghcr.io/rene-roscher/php
- **Issues:** https://github.com/Rene-Roscher/php/issues

## Architecture

- **Base:** Alpine Linux 3.19
- **Process Manager:** S6-Overlay v3
- **Web Server:** Nginx
- **PHP:** FPM with OPcache JIT
- **SSL:** Certbot with auto-renewal
- **Cron:** Built-in for Laravel scheduler

For detailed architecture and testing results, see [CLAUDE.md](CLAUDE.md) and [TEST-RESULTS.md](TEST-RESULTS.md).

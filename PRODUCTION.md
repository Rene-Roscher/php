# Production Deployment Guide

## 🚀 Production Readiness Checklist

### Pre-Deployment

- [ ] **Environment Variables Set**
  - `APP_ENV=production`
  - `APP_DEBUG=false`
  - `APP_KEY` generated (Laravel)
  - Database credentials secure

- [ ] **Security Hardened**
  - [ ] SSL Certificates configured (`CERTBOT_ENABLED=true`)
  - [ ] `PHP_DISABLE_FUNCTIONS` set (optional but recommended)
  - [ ] Firewall rules configured (only 80, 443 exposed)
  - [ ] Strong database passwords
  - [ ] No debug/development extensions (Xdebug disabled)

- [ ] **Performance Optimized**
  - [ ] `OPCACHE_VALIDATE_TIMESTAMPS=0` (production)
  - [ ] `OPCACHE_JIT=tracing` enabled
  - [ ] FPM pool sized for your server (see formulas below)
  - [ ] Laravel optimizations: `LARAVEL_OPTIMIZE_ON_BOOT=true`

- [ ] **Monitoring & Logging**
  - [ ] Health checks enabled (`HEALTHCHECK_ENABLED=true`)
  - [ ] Log aggregation configured (stdout/stderr)
  - [ ] Error tracking (Sentry, Bugsnag, etc.)

- [ ] **Backup Strategy**
  - [ ] Database backups automated
  - [ ] Volume backups scheduled (`/etc/letsencrypt`, uploaded files)
  - [ ] Backup restore tested

---

## ⚙️ Critical Environment Variables

### Security (MUST SET)

```yaml
environment:
  APP_ENV: production
  APP_DEBUG: "false"

  # Disable dangerous PHP functions
  PHP_DISABLE_FUNCTIONS: "exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source"
```

### Performance (RECOMMENDED)

```yaml
environment:
  # OPcache - Maximum Performance
  OPCACHE_ENABLE: "1"
  OPCACHE_MEMORY_CONSUMPTION: 256              # Increase if many files
  OPCACHE_MAX_ACCELERATED_FILES: 20000
  OPCACHE_VALIDATE_TIMESTAMPS: "0"             # IMPORTANT: Disable for production
  OPCACHE_JIT: tracing
  OPCACHE_JIT_BUFFER_SIZE: 100M

  # Realpath Cache - Critical for Laravel
  REALPATH_CACHE_SIZE: 4096k
  REALPATH_CACHE_TTL: 600

  # PHP-FPM Pool Sizing (see formulas below)
  FPM_PM_TYPE: dynamic
  FPM_PM_MAX_CHILDREN: 50                      # Adjust based on RAM!
  FPM_PM_START_SERVERS: 10
  FPM_PM_MIN_SPARE_SERVERS: 5
  FPM_PM_MAX_SPARE_SERVERS: 15
  FPM_PM_MAX_REQUESTS: 500                     # Prevent memory leaks
```

---

## 📐 FPM Pool Sizing Formulas

### Dynamic Mode (Recommended for most cases)

```
Available RAM for PHP = Total RAM - (System + Database + Other services)

FPM_PM_MAX_CHILDREN = Available RAM / Average Memory per Request

# Example: 4GB Server
# - System: 512MB
# - MySQL: 1GB
# - Other: 512MB
# = Available: 2GB

# If average PHP request uses 64MB:
FPM_PM_MAX_CHILDREN = 2048MB / 64MB = 32

# Conservative settings:
FPM_PM_MAX_CHILDREN: 25
FPM_PM_START_SERVERS: 5
FPM_PM_MIN_SPARE_SERVERS: 3
FPM_PM_MAX_SPARE_SERVERS: 10
```

### Static Mode (High-traffic, predictable load)

Use when you know exact traffic patterns and want maximum performance:

```yaml
FPM_PM_TYPE: static
FPM_PM_MAX_CHILDREN: 50  # All children always running
```

**Warning:** Static mode uses more RAM but has zero overhead for spawning workers.

### OnDemand Mode (Low-traffic, resource-constrained)

Good for VPS with limited RAM:

```yaml
FPM_PM_TYPE: ondemand
FPM_PM_MAX_CHILDREN: 50
FPM_PM_PROCESS_IDLE_TIMEOUT: 10s  # Kill idle workers after 10s
```

---

## 🔒 Security Best Practices

### 1. SSL/TLS Configuration

**Minimum:**
```yaml
CERTBOT_ENABLED: "true"
APP_URL: https://yourdomain.com/  # Auto-configures SSL
CERTBOT_EMAIL: admin@yourdomain.com
```

**Auto-Renewal:** Cron runs 2x daily (00:00, 12:00) - certificates renew automatically.

**HTTP → HTTPS Redirect:** Automatic when certificates exist.

### 2. File Permissions

The image handles permissions automatically:
- `/var/www`: `755` owned by `www-data:www-data`
- PHP-FPM socket: `0660` (`www-data:www-data`, nginx in www-data group)
- Session directory: `1733` (sticky bit, safe for multi-user)

**Never:**
- Run container as root in production
- Use `chmod 777` on application directories
- Disable SELinux/AppArmor without good reason

### 3. Disable Dangerous Functions

```yaml
PHP_DISABLE_FUNCTIONS: "exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source"
```

**Note:** Some packages (e.g., Laravel Excel) may need `proc_open`. Test before deploying!

### 4. Environment Secrets

**DO NOT commit:**
- `.env` files with real credentials
- Database passwords
- API keys

**Use:**
- Docker secrets (Swarm)
- Kubernetes secrets
- Vault/AWS Secrets Manager

---

## 🚨 Troubleshooting Production Issues

### Container Fails Health Check

```bash
# Check health check script
docker exec <container> /usr/local/bin/healthcheck.sh

# View detailed status
docker inspect <container> | jq '.[0].State.Health'
```

**Common causes:**
- PHP-FPM crashed (check: `docker logs <container>`)
- Nginx config error (check: `docker exec <container> nginx -t`)
- Database connection failed (check Laravel `.env`)

### High Memory Usage

```bash
# Check FPM pool status
curl http://localhost/status?full

# Check active workers and memory
docker exec <container> ps aux | grep php-fpm
```

**Solutions:**
- Reduce `FPM_PM_MAX_CHILDREN`
- Enable `FPM_PM_MAX_REQUESTS` (default: 500) to recycle workers
- Check for memory leaks in application code

### OPcache Full

```bash
# Check OPcache status
docker exec <container> php -r "print_r(opcache_get_status());"
```

**Symptoms:**
- `oom_restarts` increasing
- `cache_full` errors

**Solutions:**
```yaml
OPCACHE_MEMORY_CONSUMPTION: 512  # Increase from 256
OPCACHE_MAX_ACCELERATED_FILES: 50000  # If many files
```

### Slow Requests

```bash
# Check FPM slow log
docker exec <container> tail -f /var/log/php-fpm/slow.log
```

**FPM logs requests > 5s by default.**

**Solutions:**
- Optimize database queries
- Add indexes
- Enable Laravel query caching
- Check `FPM_REQUEST_SLOWLOG_TIMEOUT` setting

### SSL Certificate Issues

```bash
# Check certificates exist
docker exec <container> ls -la /etc/letsencrypt/live/

# Check Nginx SSL config
docker exec <container> cat /etc/nginx/http.d/default.conf | grep ssl

# Check Certbot logs
docker exec <container> certbot certificates
```

**Common issues:**
- `CERTBOT_DOMAINS` doesn't match actual domain
- Port 80 blocked (Certbot needs it for validation)
- Rate limit hit (Let's Encrypt: 50 certs/week)

---

## 📊 Monitoring & Observability

### Health Endpoint

Built-in health check at `/health`:

```bash
curl http://localhost/health
# Response: healthy
```

### PHP-FPM Status

Available at `/status` (localhost only):

```bash
# Summary
curl http://localhost/status

# Full details
curl http://localhost/status?full
curl http://localhost/status?json
```

**Metrics:**
- `active processes` - Currently processing requests
- `idle processes` - Waiting for requests
- `total processes` - active + idle
- `max children reached` - Pool exhausted (increase `FPM_PM_MAX_CHILDREN`)

### Application Logs

All logs go to stdout/stderr (Docker best practice):

```bash
# Follow all logs
docker logs -f <container>

# Filter PHP errors
docker logs <container> 2>&1 | grep -i error

# Filter slow requests
docker logs <container> 2>&1 | grep -i slow
```

### Metrics Collection

Export metrics to Prometheus/Grafana:

1. **PHP-FPM Exporter:** Use `hipages/php-fpm_exporter`
2. **Nginx Exporter:** Use `nginx-prometheus-exporter`
3. **Application Metrics:** Laravel Telescope, Horizon

---

## 🔄 Zero-Downtime Deployment

### Using Docker Compose

```bash
# 1. Pull new image
docker-compose pull

# 2. Recreate only changed services
docker-compose up -d

# 3. Run migrations (if needed)
docker-compose exec app php artisan migrate --force

# 4. Clear OPcache (force reload)
docker-compose exec app kill -USR2 1  # Reload PHP-FPM
```

**Note:** Container restart clears OPcache automatically (`OPCACHE_VALIDATE_TIMESTAMPS=0`).

### Using Docker Swarm

```bash
# Rolling update (zero downtime)
docker service update --image ghcr.io/rene-roscher/php:8.3 app

# Force update (pull new image)
docker service update --force --image ghcr.io/rene-roscher/php:8.3 app
```

### Using Kubernetes

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1
```

---

## 📦 Backup & Disaster Recovery

### Critical Data to Backup

1. **Database** (daily)
   ```bash
   docker exec <db-container> mysqldump -u root -p${PASS} ${DB} | gzip > backup-$(date +%F).sql.gz
   ```

2. **Uploaded Files** (daily/hourly depending on upload frequency)
   ```bash
   tar czf storage-$(date +%F).tar.gz ./storage/app/public/
   ```

3. **SSL Certificates** (weekly, or after renewal)
   ```bash
   docker run --rm -v certbot:/data -v $(pwd):/backup alpine tar czf /backup/certbot-$(date +%F).tar.gz /data
   ```

4. **Environment Config** (on change)
   ```bash
   # Store encrypted in version control
   gpg -c .env.production
   git add .env.production.gpg
   ```

### Restore Procedure

```bash
# 1. Stop containers
docker-compose down

# 2. Restore database
docker-compose up -d database
docker exec -i <db-container> mysql -u root -p${PASS} ${DB} < backup.sql

# 3. Restore files
tar xzf storage-backup.tar.gz -C ./

# 4. Restore certificates
docker run --rm -v certbot:/data -v $(pwd):/backup alpine tar xzf /backup/certbot-backup.tar.gz -C /

# 5. Start application
docker-compose up -d
```

---

## 🎯 Performance Benchmarks

Expected performance with recommended settings:

| Server | RAM | FPM Children | Requests/sec | Response Time |
|--------|-----|--------------|--------------|---------------|
| Small VPS | 2GB | 20 | ~100 | <100ms |
| Medium | 4GB | 50 | ~250 | <50ms |
| Large | 8GB+ | 100+ | ~500+ | <30ms |

**Note:** Actual performance depends on application code, database, and caching.

---

## 📚 Additional Resources

- [Laravel Performance Optimization](https://laravel.com/docs/deployment)
- [PHP-FPM Tuning Guide](https://www.php.net/manual/en/install.fpm.configuration.php)
- [Nginx Performance Tuning](https://www.nginx.com/blog/tuning-nginx/)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)

---

## 🆘 Getting Help

1. **Check logs:** `docker logs <container>`
2. **Run health check:** `docker exec <container> /usr/local/bin/healthcheck.sh`
3. **Check documentation:** [README.md](README.md)
4. **Report issues:** [GitHub Issues](https://github.com/Rene-Roscher/php/issues)

#!/usr/bin/with-contenv bash
set -e

# Check if Laravel application exists
if [ ! -f "/var/www/artisan" ]; then
    echo "[Laravel] artisan not found, skipping Laravel setup"
    exit 0
fi

echo "[Laravel] Setting up Laravel environment..."

# ALWAYS set permissions (even if optimization disabled)
# Critical for mounted volumes where host permissions override container
if [ -d "/var/www/storage" ]; then
    echo "[Laravel] Setting storage permissions..."
    chown -R www-data:www-data /var/www/storage
    chmod -R 775 /var/www/storage
fi

if [ -d "/var/www/bootstrap/cache" ]; then
    echo "[Laravel] Setting bootstrap/cache permissions..."
    chown -R www-data:www-data /var/www/bootstrap/cache
    chmod -R 775 /var/www/bootstrap/cache
fi

# ALWAYS regenerate config cache to prevent stale ENV (127.0.0.1 redis host etc)
# Using config:cache instead of config:clear to avoid OPcache issues
# (OPCACHE_VALIDATE_TIMESTAMPS=0 means deleted files stay cached!)
echo "[Laravel] Regenerating config cache with fresh ENV values..."
php artisan config:cache 2>/dev/null || true

# Skip other optimizations if disabled
if [ "${LARAVEL_OPTIMIZE_ON_BOOT:-true}" != "true" ]; then
    echo "[Laravel] Optimization disabled via ENV (permissions applied, config cache regenerated)"
    exit 0
fi

echo "[Laravel] Running optimizations..."

# Run Laravel optimizations
cd /var/www

# Storage link (if enabled)
if [ "${AUTORUN_LARAVEL_STORAGE_LINK:-false}" = "true" ]; then
    echo "[Laravel] Creating storage link..."
    php artisan storage:link --force 2>/dev/null || true
fi

# Database migrations (if enabled)
if [ "${AUTORUN_LARAVEL_MIGRATION:-false}" = "true" ]; then
    echo "[Laravel] Running migrations..."
    php artisan migrate --force || true
fi

if [ "${AUTORUN_LARAVEL_MIGRATION_SEED:-false}" = "true" ]; then
    echo "[Laravel] Running migrations with seed..."
    php artisan migrate --seed --force || true
fi

if [ "${AUTORUN_LARAVEL_MIGRATION_FRESH_SEED:-false}" = "true" ]; then
    echo "[Laravel] Running fresh migrations with seed..."
    php artisan migrate:fresh --seed --force || true
fi

# Cache optimizations
if [ "${APP_ENV:-production}" = "production" ]; then
    echo "[Laravel] Running production optimizations..."

    php artisan config:cache || true
    php artisan route:cache || true
    php artisan view:cache || true
    php artisan event:cache || true

    # Optional: Uncomment if using Ziggy
    # php artisan ziggy:generate 2>/dev/null || true
else
    echo "[Laravel] Non-production environment, clearing caches..."
    php artisan config:clear || true
    php artisan route:clear || true
    php artisan view:clear || true
    php artisan cache:clear || true
fi

echo "[Laravel] Optimization complete!"

exit 0

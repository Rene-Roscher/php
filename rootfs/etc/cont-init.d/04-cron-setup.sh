#!/usr/bin/with-contenv bash
set -e

if [ "${CRON_ENABLED:-true}" != "true" ]; then
    echo "[Cron] Disabled via ENV"
    exit 0
fi

echo "[Cron] Setting up scheduled tasks..."

# Initialize crontab
touch /etc/crontabs/root

# Laravel Scheduler (if enabled)
if [ "${LARAVEL_SCHEDULE_ENABLED:-true}" = "true" ] && [ -f "/var/www/artisan" ]; then
    SCHEDULE="${CRON_SCHEDULE_LARAVEL:-* * * * *}"
    echo "${SCHEDULE} cd /var/www && php artisan schedule:run >> /dev/null 2>&1" >> /etc/crontabs/root
    echo "[Cron] Laravel scheduler added: ${SCHEDULE}"
fi

# Custom cron jobs (semicolon separated)
if [ -n "${CRON_CUSTOM}" ]; then
    echo "[Cron] Adding custom cron jobs..."
    echo "${CRON_CUSTOM}" | tr ';' '\n' >> /etc/crontabs/root
fi

# Set proper permissions
chmod 0644 /etc/crontabs/root

echo "[Cron] Crontab configured:"
cat /etc/crontabs/root

echo "[Cron] Setup complete!"

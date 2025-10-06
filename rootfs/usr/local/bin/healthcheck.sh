#!/bin/bash

# Health Check Script for Docker Container
# Checks: PHP-FPM, Nginx, and Application Health

set -e

# Configuration
HEALTHCHECK_ENABLED="${HEALTHCHECK_ENABLED:-true}"
HEALTHCHECK_PATH="${HEALTHCHECK_PATH:-/health}"
FPM_PING_PATH="${FPM_PING_PATH:-/ping}"
HTTP_TIMEOUT=3

if [ "${HEALTHCHECK_ENABLED}" != "true" ]; then
    exit 0
fi

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check counter
CHECKS_PASSED=0
CHECKS_TOTAL=0

check_service() {
    local service=$1
    local check_cmd=$2
    local description=$3

    CHECKS_TOTAL=$((CHECKS_TOTAL + 1))

    if eval "$check_cmd" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $service: $description"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $service: $description"
        return 1
    fi
}

echo "=== Docker Container Health Check ==="
echo

# 1. Check PHP-FPM process
check_service "PHP-FPM" \
    "pgrep -x php-fpm > /dev/null" \
    "Process running"

# 2. Check PHP-FPM socket/TCP
if [ -S "${FPM_LISTEN:-/run/php/php-fpm.sock}" ]; then
    check_service "PHP-FPM" \
        "test -S ${FPM_LISTEN}" \
        "Socket exists and accessible"
fi

# 3. Check PHP-FPM ping endpoint via fcgi
check_service "PHP-FPM" \
    "SCRIPT_FILENAME=${FPM_PING_PATH} REQUEST_METHOD=GET cgi-fcgi -bind -connect ${FPM_LISTEN}" \
    "Ping endpoint responsive"

# 4. Check Nginx process
check_service "Nginx" \
    "pgrep -x nginx > /dev/null" \
    "Process running"

# 5. Check Nginx HTTP
check_service "Nginx" \
    "curl -f -s -o /dev/null --max-time ${HTTP_TIMEOUT} http://localhost${HEALTHCHECK_PATH}" \
    "HTTP endpoint responsive"

# 6. Check Nginx configuration
check_service "Nginx" \
    "nginx -t" \
    "Configuration valid"

# 7. Check Cron (if enabled)
if [ "${CRON_ENABLED:-true}" = "true" ]; then
    check_service "Cron" \
        "pgrep -x crond > /dev/null" \
        "Process running"
fi

# 8. Check critical directories
check_service "Filesystem" \
    "test -d /var/www && test -w /var/www" \
    "/var/www writable"

check_service "Filesystem" \
    "test -d /var/lib/php/sessions && test -w /var/lib/php/sessions" \
    "Session directory writable"

# 9. Application-specific health check (Laravel)
if [ -f "/var/www/artisan" ]; then
    # Try Laravel health check route if exists
    if curl -f -s -o /dev/null --max-time ${HTTP_TIMEOUT} http://localhost/api/health 2>/dev/null; then
        check_service "Application" \
            "curl -f -s -o /dev/null --max-time ${HTTP_TIMEOUT} http://localhost/api/health" \
            "Laravel health endpoint OK"
    fi
fi

echo
echo "=== Health Check Summary ==="
echo "Passed: ${CHECKS_PASSED}/${CHECKS_TOTAL}"

# Exit code based on critical checks
if [ ${CHECKS_PASSED} -ge $((CHECKS_TOTAL - 2)) ]; then
    echo -e "${GREEN}Status: HEALTHY${NC}"
    exit 0
else
    echo -e "${RED}Status: UNHEALTHY${NC}"
    exit 1
fi

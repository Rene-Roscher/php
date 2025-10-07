#!/usr/bin/with-contenv bash
set -e

echo "[Init] Generating runtime configurations from ENV variables..."

# Delete marker file from previous run
rm -f /tmp/.services-ready 2>/dev/null || true

########################################
# Fix nginx user permissions for Unix socket access
########################################
# Add nginx user to www-data group so it can access PHP-FPM socket
addgroup nginx www-data 2>/dev/null || true
echo "[Init] Added nginx user to www-data group for socket access"

########################################
# Auto-derive Nginx server_name from APP_URL
########################################
if [ -n "${APP_URL}" ]; then
    # Extract domain from APP_URL (remove protocol and trailing slash)
    DOMAIN_FROM_URL=$(echo "${APP_URL}" | sed -E 's~^https?://~~' | sed 's~/$~~')
    export NGINX_SERVER_NAME="${NGINX_SERVER_NAME:-$DOMAIN_FROM_URL}"
    echo "[Init] Auto-derived server_name from APP_URL: ${NGINX_SERVER_NAME}"

    # IMPORTANT: Also set CERTBOT_DOMAINS if not already set
    # This must happen BEFORE nginx config generation (used in SSL template check)
    if [ -z "${CERTBOT_DOMAINS}" ] || [ "${CERTBOT_DOMAINS}" = "example.com,www.example.com" ]; then
        export CERTBOT_DOMAINS="${DOMAIN_FROM_URL}"
        echo "[Init] Auto-derived CERTBOT_DOMAINS from APP_URL: ${CERTBOT_DOMAINS}"
    fi
else
    # Fallback to catch-all
    export NGINX_SERVER_NAME="${NGINX_SERVER_NAME:-_}"
    echo "[Init] Using server_name: ${NGINX_SERVER_NAME}"
fi

########################################
# Socket Type Detection (используется für PHP-FPM UND Nginx)
########################################
FPM_LISTEN_VALUE="${FPM_LISTEN:-/run/php/php-fpm.sock}"

if [[ "${FPM_LISTEN_VALUE}" == *":"* ]]; then
    # TCP Socket (enthält :)
    export FPM_PASS="${FPM_LISTEN_VALUE}"
    echo "[Init] Using TCP socket: ${FPM_PASS}"
    IS_UNIX_SOCKET=0
else
    # Unix Socket
    export FPM_PASS="unix:${FPM_LISTEN_VALUE}"
    echo "[Init] Using Unix socket: ${FPM_PASS}"
    IS_UNIX_SOCKET=1
fi

########################################
# PHP Configuration
########################################
cat > /usr/local/etc/php/conf.d/99-runtime.ini <<EOF
; Runtime PHP Configuration - Generated from ENV
memory_limit = ${PHP_MEMORY_LIMIT:-256M}
max_execution_time = ${PHP_MAX_EXECUTION_TIME:-60}
max_input_time = ${PHP_MAX_INPUT_TIME:-60}
max_input_vars = ${PHP_MAX_INPUT_VARS:-1000}

; Upload Settings
upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE:-200M}
post_max_size = ${PHP_POST_MAX_SIZE:-200M}
max_file_uploads = ${PHP_MAX_FILE_UPLOADS:-20}

; Error Handling
display_errors = ${PHP_DISPLAY_ERRORS:-Off}
display_startup_errors = ${PHP_DISPLAY_STARTUP_ERRORS:-Off}
error_reporting = ${PHP_ERROR_REPORTING:-E_ALL & ~E_DEPRECATED & ~E_STRICT}
log_errors = ${PHP_LOG_ERRORS:-On}
error_log = ${PHP_ERROR_LOG:-/var/log/php/error.log}

; Timezone
date.timezone = ${PHP_DATE_TIMEZONE:-UTC}

; Security
expose_php = ${PHP_EXPOSE_PHP:-Off}
allow_url_fopen = ${PHP_ALLOW_URL_FOPEN:-On}
allow_url_include = ${PHP_ALLOW_URL_INCLUDE:-Off}
disable_functions = ${PHP_DISABLE_FUNCTIONS}

; Performance - Realpath Cache (CRITICAL für Laravel!)
; Laravel hat viele Dateien - großer Cache verhindert stat() Calls
realpath_cache_size = ${REALPATH_CACHE_SIZE:-4096k}
realpath_cache_ttl = ${REALPATH_CACHE_TTL:-600}

; Preload (wenn verfügbar) - lädt häufig genutzte Files beim Start
; opcache.preload = /var/www/preload.php
; opcache.preload_user = www-data

; Session
session.save_handler = ${SESSION_SAVE_HANDLER:-files}
session.save_path = ${SESSION_SAVE_PATH:-/var/lib/php/sessions}
session.gc_probability = ${SESSION_GC_PROBABILITY:-1}
session.gc_divisor = ${SESSION_GC_DIVISOR:-1000}
session.gc_maxlifetime = ${SESSION_GC_MAXLIFETIME:-1440}
EOF

########################################
# OPcache Configuration (Laravel-Optimized)
########################################
if [ "${OPCACHE_ENABLE:-1}" = "1" ]; then
cat > /usr/local/etc/php/conf.d/98-opcache.ini <<EOF
; OPcache Configuration - Laravel-Optimized
opcache.enable = 1
opcache.enable_cli = ${OPCACHE_ENABLE_CLI:-0}
opcache.memory_consumption = ${OPCACHE_MEMORY_CONSUMPTION:-256}
opcache.interned_strings_buffer = ${OPCACHE_INTERNED_STRINGS_BUFFER:-16}
opcache.max_accelerated_files = ${OPCACHE_MAX_ACCELERATED_FILES:-20000}
opcache.max_wasted_percentage = ${OPCACHE_MAX_WASTED_PERCENTAGE:-5}

; Validation (Production: timestamps=0 for max performance)
opcache.validate_timestamps = ${OPCACHE_VALIDATE_TIMESTAMPS:-0}
opcache.revalidate_freq = ${OPCACHE_REVALIDATE_FREQ:-0}
opcache.revalidate_path = ${OPCACHE_REVALIDATE_PATH:-0}

; Laravel Performance Optimizations
opcache.save_comments = 1
opcache.fast_shutdown = 1
opcache.enable_file_override = 1
opcache.optimization_level = ${OPCACHE_OPTIMIZATION_LEVEL:-0x7FFEBFFF}

; Huge Pages (wenn verfügbar, massive Performance-Boost)
opcache.huge_code_pages = ${OPCACHE_HUGE_CODE_PAGES:-0}

; JIT Compiler (PHP 8.0+) - Laravel profitiert massiv davon
opcache.jit = ${OPCACHE_JIT:-tracing}
opcache.jit_buffer_size = ${OPCACHE_JIT_BUFFER_SIZE:-100M}

; File Cache für Multi-Container Setups (optional)
opcache.file_cache = ${OPCACHE_FILE_CACHE}
opcache.file_cache_only = ${OPCACHE_FILE_CACHE_ONLY:-0}

; Preloading (Laravel 8+) - wenn konfiguriert
$([ -f "/var/www/preload.php" ] && echo "opcache.preload = /var/www/preload.php" || echo "; opcache.preload not configured")
$([ -f "/var/www/preload.php" ] && echo "opcache.preload_user = www-data" || echo "")
EOF
else
    echo "[Init] OPcache disabled via ENV"
fi

########################################
# PHP-FPM Pool Configuration
########################################
cat > /usr/local/etc/php-fpm.d/zz-runtime.conf <<EOF
; Runtime FPM Pool Configuration - Generated from ENV
[www]
user = www-data
group = www-data

; Socket Configuration
; Unix Socket (default): /run/php/php-fpm.sock
; TCP Socket (alternative): 127.0.0.1:9000
listen = ${FPM_LISTEN_VALUE}
EOF

# Only set socket owner/group/mode for Unix sockets
if [ $IS_UNIX_SOCKET -eq 1 ]; then
cat >> /usr/local/etc/php-fpm.d/zz-runtime.conf <<EOF
; Unix Socket Permissions (nginx is in www-data group)
listen.owner = ${FPM_LISTEN_OWNER:-www-data}
listen.group = ${FPM_LISTEN_GROUP:-www-data}
listen.mode = ${FPM_LISTEN_MODE:-0660}
EOF
fi

cat >> /usr/local/etc/php-fpm.d/zz-runtime.conf <<EOF

; Process Manager
pm = ${FPM_PM_TYPE:-dynamic}
EOF

# PM Type Specific Settings
if [ "${FPM_PM_TYPE:-dynamic}" = "static" ]; then
cat >> /usr/local/etc/php-fpm.d/zz-runtime.conf <<EOF
pm.max_children = ${FPM_PM_MAX_CHILDREN:-50}
EOF
elif [ "${FPM_PM_TYPE:-dynamic}" = "dynamic" ]; then
cat >> /usr/local/etc/php-fpm.d/zz-runtime.conf <<EOF
pm.max_children = ${FPM_PM_MAX_CHILDREN:-50}
pm.start_servers = ${FPM_PM_START_SERVERS:-10}
pm.min_spare_servers = ${FPM_PM_MIN_SPARE_SERVERS:-5}
pm.max_spare_servers = ${FPM_PM_MAX_SPARE_SERVERS:-15}
EOF
elif [ "${FPM_PM_TYPE:-dynamic}" = "ondemand" ]; then
cat >> /usr/local/etc/php-fpm.d/zz-runtime.conf <<EOF
pm.max_children = ${FPM_PM_MAX_CHILDREN:-50}
pm.process_idle_timeout = ${FPM_PM_PROCESS_IDLE_TIMEOUT:-10s}
EOF
fi

# Common PM Settings
cat >> /usr/local/etc/php-fpm.d/zz-runtime.conf <<EOF
pm.max_requests = ${FPM_PM_MAX_REQUESTS:-500}

; Process Control Timeout (nicht verfügbar in PHP-FPM 8.3)
; process_control_timeout = ${FPM_PROCESS_CONTROL_TIMEOUT:-10s}

; Status/Monitoring
pm.status_path = ${FPM_STATUS_PATH:-/status}
ping.path = ${FPM_PING_PATH:-/ping}
ping.response = ${FPM_PING_RESPONSE:-pong}

; Logging (Laravel-Optimiert)
access.log = ${FPM_ACCESS_LOG:-/dev/stdout}
access.format = "%R - %u %t \"%m %r\" %s %f %{mili}d %{kilo}M %C%%"
slowlog = ${FPM_SLOWLOG:-/var/log/php-fpm/slow.log}
request_slowlog_timeout = ${FPM_REQUEST_SLOWLOG_TIMEOUT:-5s}
request_slowlog_trace_depth = ${FPM_REQUEST_SLOWLOG_TRACE_DEPTH:-20}
request_terminate_timeout = ${FPM_REQUEST_TERMINATE_TIMEOUT:-30s}

; Catch output from workers (wichtig für Laravel Logs)
catch_workers_output = ${FPM_CATCH_WORKERS_OUTPUT:-yes}
decorate_workers_output = ${FPM_DECORATE_WORKERS_OUTPUT:-no}

; Environment Variables (Laravel braucht diese!)
clear_env = no

; Resource Limits (optional, für High-Load)
; rlimit_files = ${FPM_RLIMIT_FILES:-65536}
; rlimit_core = ${FPM_RLIMIT_CORE:-0}
EOF

########################################
# Nginx Configuration
########################################
# Ensure nginx http.d directory exists
mkdir -p /etc/nginx/http.d

cat > /etc/nginx/http.d/99-runtime.conf <<EOF
# Runtime Nginx Configuration - Generated from ENV

# Client Settings (client_max_body_size and keepalive_timeout set in nginx.conf to avoid duplicate)
client_body_buffer_size ${NGINX_CLIENT_BODY_BUFFER_SIZE:-128k};
client_header_buffer_size ${NGINX_CLIENT_HEADER_BUFFER_SIZE:-1k};
large_client_header_buffers ${NGINX_LARGE_CLIENT_HEADER_BUFFERS:-4 8k};

# Timeouts (keepalive_timeout in nginx.conf)
send_timeout ${NGINX_SEND_TIMEOUT:-60s};
client_body_timeout ${NGINX_CLIENT_BODY_TIMEOUT:-60s};
client_header_timeout ${NGINX_CLIENT_HEADER_TIMEOUT:-60s};

# FastCGI Settings
fastcgi_connect_timeout ${NGINX_FASTCGI_CONNECT_TIMEOUT:-60s};
fastcgi_send_timeout ${NGINX_FASTCGI_SEND_TIMEOUT:-60s};
fastcgi_read_timeout ${NGINX_FASTCGI_READ_TIMEOUT:-60s};
fastcgi_buffers ${NGINX_FASTCGI_BUFFERS:-8 16k};
fastcgi_buffer_size ${NGINX_FASTCGI_BUFFER_SIZE:-32k};
fastcgi_busy_buffers_size ${NGINX_FASTCGI_BUSY_BUFFERS_SIZE:-64k};
EOF

# Generate main nginx.conf from template
export NGINX_WORKER_PROCESSES=${NGINX_WORKER_PROCESSES:-auto}
export NGINX_WORKER_CONNECTIONS=${NGINX_WORKER_CONNECTIONS:-2048}
export NGINX_CLIENT_MAX_BODY_SIZE=${NGINX_CLIENT_MAX_BODY_SIZE:-200M}

envsubst '${NGINX_WORKER_PROCESSES} ${NGINX_WORKER_CONNECTIONS} ${NGINX_CLIENT_MAX_BODY_SIZE}' \
    < /etc/templates/nginx.conf > /etc/nginx/nginx.conf

# Export required ENV variables for server block templates
export NGINX_WEBROOT=${NGINX_WEBROOT:-/var/www/public}
export APP_ENV=${APP_ENV:-production}
export NGINX_FASTCGI_BUFFER_SIZE=${NGINX_FASTCGI_BUFFER_SIZE:-32k}
export NGINX_FASTCGI_BUFFERS=${NGINX_FASTCGI_BUFFERS:-8 16k}
export NGINX_FASTCGI_BUSY_BUFFERS_SIZE=${NGINX_FASTCGI_BUSY_BUFFERS_SIZE:-64k}
export NGINX_FASTCGI_CONNECT_TIMEOUT=${NGINX_FASTCGI_CONNECT_TIMEOUT:-60s}
export NGINX_FASTCGI_SEND_TIMEOUT=${NGINX_FASTCGI_SEND_TIMEOUT:-60s}
export NGINX_FASTCGI_READ_TIMEOUT=${NGINX_FASTCGI_READ_TIMEOUT:-60s}

# FPM_PASS is already set at the top of the script

# Check if SSL certificates exist and use appropriate template
CERT_DIR="/etc/letsencrypt/live"
export CERTBOT_DOMAIN="${CERTBOT_DOMAINS%%,*}"  # Get first domain from comma-separated list

if [ "${CERTBOT_ENABLED:-false}" = "true" ] && [ -d "${CERT_DIR}/${CERTBOT_DOMAIN}" ] && [ -f "${CERT_DIR}/${CERTBOT_DOMAIN}/fullchain.pem" ]; then
    echo "[Init] SSL certificates found for ${CERTBOT_DOMAIN}, using SSL config"
    # Use SSL template with HTTPS + HTTP redirect
    envsubst '${NGINX_SERVER_NAME} ${NGINX_WEBROOT} ${FPM_PASS} ${APP_ENV} ${CERTBOT_DOMAIN} ${NGINX_FASTCGI_BUFFER_SIZE} ${NGINX_FASTCGI_BUFFERS} ${NGINX_FASTCGI_BUSY_BUFFERS_SIZE} ${NGINX_FASTCGI_CONNECT_TIMEOUT} ${NGINX_FASTCGI_SEND_TIMEOUT} ${NGINX_FASTCGI_READ_TIMEOUT}' \
        < /etc/templates/nginx-laravel-ssl.conf > /etc/nginx/http.d/default.conf
else
    echo "[Init] No SSL certificates found, using HTTP-only config"
    # Use HTTP-only template
    envsubst '${NGINX_SERVER_NAME} ${NGINX_WEBROOT} ${FPM_PASS} ${APP_ENV} ${NGINX_FASTCGI_BUFFER_SIZE} ${NGINX_FASTCGI_BUFFERS} ${NGINX_FASTCGI_BUSY_BUFFERS_SIZE} ${NGINX_FASTCGI_CONNECT_TIMEOUT} ${NGINX_FASTCGI_SEND_TIMEOUT} ${NGINX_FASTCGI_READ_TIMEOUT}' \
        < /etc/templates/nginx-laravel.conf > /etc/nginx/http.d/default.conf
fi

echo "[Init] Configurations generated successfully!"


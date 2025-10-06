########################################
# Laravel PHP Docker - Universal Image
# Configure via ENV at runtime
########################################

# Build Arguments
ARG PHP_VERSION=8.3
ARG ALPINE_VERSION=3.19
ARG S6_OVERLAY_VERSION=3.1.6.2

# Optional Extensions
ARG INSTALL_REDIS=true
ARG INSTALL_XDEBUG=false
ARG INSTALL_IMAGICK=false
ARG INSTALL_SWOOLE=false

########################################
# Stage 1: S6 Overlay Downloader
########################################
FROM alpine:${ALPINE_VERSION} AS s6-downloader

ARG S6_OVERLAY_VERSION
ARG TARGETARCH

WORKDIR /tmp

RUN apk add --no-cache curl && \
    case ${TARGETARCH} in \
        amd64) S6_ARCH="x86_64" ;; \
        arm64) S6_ARCH="aarch64" ;; \
        arm) S6_ARCH="armhf" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    curl -L "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" -o /tmp/s6-overlay-noarch.tar.xz && \
    curl -L "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" -o /tmp/s6-overlay-arch.tar.xz && \
    curl -L "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-noarch.tar.xz" -o /tmp/s6-overlay-symlinks.tar.xz

########################################
# Stage 2: Base Image with Extensions
########################################
FROM php:${PHP_VERSION}-fpm-alpine${ALPINE_VERSION} AS base

# Build Args
ARG INSTALL_REDIS
ARG INSTALL_XDEBUG
ARG INSTALL_IMAGICK
ARG INSTALL_SWOOLE

# Install PHP Extension Installer
COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/

# Install Core Extensions (always needed)
RUN install-php-extensions \
    bcmath \
    exif \
    gd \
    gmp \
    intl \
    opcache \
    pcntl \
    pdo_mysql \
    zip

# Install Optional Extensions
RUN if [ "$INSTALL_REDIS" = "true" ]; then install-php-extensions redis; fi && \
    if [ "$INSTALL_XDEBUG" = "true" ]; then install-php-extensions xdebug; fi && \
    if [ "$INSTALL_IMAGICK" = "true" ]; then install-php-extensions imagick; fi && \
    if [ "$INSTALL_SWOOLE" = "true" ]; then install-php-extensions swoole; fi

# Cleanup
RUN rm /usr/local/bin/install-php-extensions

########################################
# Stage 3: Runtime Image
########################################
FROM base AS runtime

# Copy S6 Overlay
COPY --from=s6-downloader /tmp/s6-overlay-noarch.tar.xz /tmp/
COPY --from=s6-downloader /tmp/s6-overlay-arch.tar.xz /tmp/
COPY --from=s6-downloader /tmp/s6-overlay-symlinks.tar.xz /tmp/

RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
    tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz && \
    tar -C / -Jxpf /tmp/s6-overlay-symlinks.tar.xz && \
    rm -f /tmp/s6-overlay-*.tar.xz

# Install runtime dependencies
RUN apk add --no-cache \
    nginx \
    git \
    curl \
    bash \
    shadow \
    certbot \
    certbot-nginx \
    fcgi \
    tzdata \
    gettext

# Create necessary directories
RUN mkdir -p \
    /var/www \
    /var/log/php \
    /var/log/php-fpm \
    /var/log/nginx \
    /var/lib/php/sessions \
    /run/php \
    /etc/s6-overlay/s6-rc.d \
    /etc/cont-init.d \
    /etc/services.d

# Create nginx user and www-data adjustments
RUN addgroup -g 82 -S www-data 2>/dev/null || true && \
    adduser -u 82 -D -S -G www-data www-data 2>/dev/null || true
# Note: nginx user added to www-data group in init script (after nginx is installed)

# Remove default www.conf to avoid conflicts with runtime config
RUN rm -f /usr/local/etc/php-fpm.d/www.conf

# Set permissions
RUN chown -R www-data:www-data /var/www /var/lib/php/sessions && \
    chmod -R 755 /var/www && \
    chmod 1733 /var/lib/php/sessions  # Sticky bit + world writable (safe for sessions)

# Set working directory
WORKDIR /var/www

# Default Environment Variables (can be overridden)
ENV PHP_VERSION=${PHP_VERSION} \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
    S6_VERBOSITY=1 \
    \
    # PHP Settings
    PHP_MEMORY_LIMIT=256M \
    PHP_MAX_EXECUTION_TIME=60 \
    PHP_UPLOAD_MAX_FILESIZE=200M \
    PHP_POST_MAX_SIZE=200M \
    \
    # FPM Settings
    FPM_PM_TYPE=dynamic \
    FPM_PM_MAX_CHILDREN=50 \
    FPM_PM_START_SERVERS=10 \
    FPM_PM_MIN_SPARE_SERVERS=5 \
    FPM_PM_MAX_SPARE_SERVERS=15 \
    FPM_PM_MAX_REQUESTS=500 \
    FPM_LISTEN=/run/php/php-fpm.sock \
    \
    # OPcache Settings
    OPCACHE_ENABLE=1 \
    OPCACHE_MEMORY_CONSUMPTION=256 \
    OPCACHE_MAX_ACCELERATED_FILES=20000 \
    OPCACHE_VALIDATE_TIMESTAMPS=0 \
    \
    # Nginx Settings
    NGINX_WEBROOT=/var/www/public \
    NGINX_CLIENT_MAX_BODY_SIZE=200M \
    \
    # Application
    APP_ENV=production \
    LARAVEL_OPTIMIZE_ON_BOOT=true \
    \
    # Logging
    LOG_LEVEL=info

# Copy configuration templates
COPY rootfs/ /

# Make scripts executable
RUN chmod +x /etc/cont-init.d/* && \
    chmod +x /usr/local/bin/*

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh || exit 1

# Expose ports
EXPOSE 80 443

# Labels
LABEL maintainer="rene.roscher@spotcreator.com" \
      org.opencontainers.image.title="Laravel PHP Docker - Universal Image" \
      org.opencontainers.image.description="Production-ready PHP ${PHP_VERSION} for Laravel - Configure via ENV" \
      org.opencontainers.image.vendor="Rene Roscher" \
      org.opencontainers.image.version="${PHP_VERSION}" \
      org.opencontainers.image.source="https://github.com/Rene-Roscher/php"

# Use S6 Overlay as init
ENTRYPOINT ["/init"]

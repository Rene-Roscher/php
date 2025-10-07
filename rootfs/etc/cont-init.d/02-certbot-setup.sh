#!/usr/bin/with-contenv bash
set -e

# Skip if Certbot is disabled
if [ "${CERTBOT_ENABLED:-true}" != "true" ]; then
    echo "[Certbot] Disabled via ENV"
    exit 0
fi

echo "[Certbot] Setting up SSL certificate management..."

# Validate required variables
if [ -z "${CERTBOT_EMAIL}" ] || [ "${CERTBOT_EMAIL}" = "admin@example.com" ]; then
    echo "[Certbot] WARNING: CERTBOT_EMAIL not set or using default. Certbot will run in test mode."
    CERTBOT_EMAIL=""
fi

# Auto-derive CERTBOT_DOMAINS from APP_URL if not explicitly set
# Note: This is duplicate logic from 01-setup-configs.sh because ENV exports
# don't persist between S6-Overlay init scripts (separate shell contexts)
if [ -n "${APP_URL}" ]; then
    DOMAIN_FROM_URL=$(echo "${APP_URL}" | sed -E 's~^https?://~~' | sed 's~/$~~')
    CERTBOT_DOMAINS="${CERTBOT_DOMAINS:-$DOMAIN_FROM_URL}"
fi

# Fallback check
if [ -z "${CERTBOT_DOMAINS}" ] || [ "${CERTBOT_DOMAINS}" = "example.com,www.example.com" ]; then
    echo "[Certbot] WARNING: CERTBOT_DOMAINS not set. SSL certificates will not be obtained."
    echo "[Certbot] Set APP_URL or CERTBOT_DOMAINS environment variable."
    exit 0
fi

echo "[Certbot] Using domain: ${CERTBOT_DOMAINS}"

# Certbot cron setup moved to 04-cron-setup.sh to avoid duplication
if [ "${CERTBOT_AUTO_RENEW:-true}" = "true" ]; then
    echo "[Certbot] Auto-renewal will be configured by cron-setup script"
fi

# Check if certificates exist
CERT_DIR="/etc/letsencrypt/live"
FIRST_DOMAIN=$(echo ${CERTBOT_DOMAINS} | cut -d',' -f1)

if [ ! -d "${CERT_DIR}/${FIRST_DOMAIN}" ]; then
    echo "[Certbot] No existing certificates found for ${FIRST_DOMAIN}"
    echo "[Certbot] Certificates will be obtained on first request via Certbot Nginx plugin"
    echo "[Certbot] Or manually run: certbot --nginx -d ${CERTBOT_DOMAINS}"
else
    echo "[Certbot] Existing certificates found for ${FIRST_DOMAIN}"
fi

# Create Certbot Nginx config snippet
mkdir -p /etc/nginx/snippets

cat > /etc/nginx/snippets/certbot.conf <<'EOF'
# Certbot Challenge Location
location /.well-known/acme-challenge/ {
    root /var/www/certbot;
    allow all;
}
EOF

# Create certbot webroot
mkdir -p /var/www/certbot
chown -R www-data:www-data /var/www/certbot

echo "[Certbot] Setup complete!"
echo "[Certbot] To obtain certificates, run:"
echo "  certbot --nginx -d ${CERTBOT_DOMAINS} --email ${CERTBOT_EMAIL} --agree-tos --non-interactive"

#!/bin/sh

# Generate UUID if not provided
if [ -z "$UUID" ]; then
    export UUID=$(uuidgen)
fi

# Dashboard Auth
if [ -z "$DASH_USER" ]; then
    export DASH_USER="admin"
fi
if [ -z "$DASH_PASS" ]; then
    export DASH_PASS="$UUID"
fi

echo "UUID: $UUID"
echo "Dashboard User: $DASH_USER"
echo "Dashboard Pass: $DASH_PASS"

# Create Basic Auth File
htpasswd -bc /etc/nginx/.htpasswd "$DASH_USER" "$DASH_PASS"

# Configure Xray
# Substitute only $UUID in xray config
envsubst < /etc/xray/config.json.template > /etc/xray/config.json

# Configure Nginx
# Crucial: Only substitute $PORT in nginx config to avoid breaking Nginx variables ($host, $uri, etc)
envsubst '${PORT}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# Configure HTML
# Substitute $UUID
envsubst < /www/index.html.template > /www/index.html

# Start Xray
echo "Starting Xray..."
/usr/bin/xray -config /etc/xray/config.json &

# Start Nginx
echo "Starting Nginx..."
mkdir -p /run/nginx
nginx -c /etc/nginx/nginx.conf

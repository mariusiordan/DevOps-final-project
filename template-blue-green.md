# /etc/nginx/conf.d/upstream.conf
# Blue/Green upstream configuration
# Only ONE server should be active at a time
# To switch: run /opt/scripts/switch-backend.sh

upstream app_backend {
    server 10.10.20.11:3000;      # prod-vm1-BLUE  (APP network) - ACTIVE
    # server 10.10.20.12:3000;    # prod-vm2-GREEN (APP network) - INACTIVE
}


=====================================================================================

# /etc/nginx/sites-enabled/app.conf
# Main nginx site configuration
# Proxies all incoming requests to the active backend (blue or green)

# ─── HTTP → HTTPS Redirect ───────────────────────────────────
server {
    listen 80;
    server_name yourdomain.com;

    # Redirect all HTTP traffic to HTTPS
    return 301 https://$host$request_uri;
}

# ─── HTTPS ───────────────────────────────────────────────────
server {
    listen 443 ssl;
    server_name yourdomain.com;

    # SSL certificates (Let's Encrypt or self-signed)
    ssl_certificate     /etc/ssl/certs/app.crt;
    ssl_certificate_key /etc/ssl/private/app.key;

    # Proxy all requests to active backend (blue or green)
    location / {
        proxy_pass         http://app_backend;
        proxy_http_version 1.1;

        # Pass real client info to the app
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;

        # WebSocket support
        proxy_set_header   Upgrade           $http_upgrade;
        proxy_set_header   Connection        "upgrade";

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout    60s;
        proxy_read_timeout    60s;
    }

    # Health check endpoint - used for smoke tests and monitoring
    location /api/health {
        proxy_pass http://app_backend/api/health;
    }
}

=====================================================================================


#!/bin/bash
# /opt/scripts/switch-backend.sh
# Blue/Green traffic switch script
#
# Usage:
#   sudo /opt/scripts/switch-backend.sh          # auto-switch to the other env
#   sudo /opt/scripts/switch-backend.sh blue     # force switch to BLUE
#   sudo /opt/scripts/switch-backend.sh green    # force switch to GREEN
#
# Blue/Green flow:
#   1. Deploy new version to idle environment
#   2. Test idle environment directly (curl http://10.10.20.12:3000/api/health)
#   3. Run this script to switch nginx traffic
#   4. Monitor for 5-10 minutes
#   5. OK  → keep new environment, old stays as fallback
#   6. NOK → run this script again to rollback

NGINX_CONF="/etc/nginx/conf.d/upstream.conf"
BLUE_IP="10.10.20.11"
GREEN_IP="10.10.20.12"
PORT="3000"

# ─── Detect current active environment ───────────────────────
CURRENT=$(grep -v "^#" "$NGINX_CONF" | grep "server 10.10.20" | awk '{print $2}' | cut -d: -f1)

# ─── Determine target environment ────────────────────────────
TARGET="${1:-}"  # optional argument: blue or green

if [ -n "$TARGET" ]; then
    # Force switch to specified environment
    if [ "$TARGET" != "blue" ] && [ "$TARGET" != "green" ]; then
        echo "❌ Invalid argument. Use: blue or green"
        exit 1
    fi
else
    # Auto-switch to the other environment
    if [ "$CURRENT" = "$BLUE_IP" ]; then
        TARGET="green"
    else
        TARGET="blue"
    fi
fi

# ─── Perform the switch ───────────────────────────────────────
if [ "$TARGET" = "green" ]; then
    TARGET_IP="$GREEN_IP"
    INACTIVE_IP="$BLUE_IP"
else
    TARGET_IP="$BLUE_IP"
    INACTIVE_IP="$GREEN_IP"
fi

# Check target environment is healthy before switching
echo "🔍 Checking $TARGET environment health..."
if ! curl -sf "http://$TARGET_IP:$PORT/api/health" > /dev/null 2>&1; then
    echo "❌ $TARGET environment is not healthy at $TARGET_IP:$PORT"
    echo "   Aborting switch. Check the application logs."
    exit 1
fi

echo "✅ $TARGET environment is healthy"

# Update nginx upstream config
sed -i "s|    server $TARGET_IP|    server $TARGET_IP|" "$NGINX_CONF"
sed -i "s|    server $INACTIVE_IP|    # server $INACTIVE_IP|" "$NGINX_CONF"
sed -i "s|    # server $TARGET_IP|    server $TARGET_IP|" "$NGINX_CONF"

# Test nginx config before reloading
if ! nginx -t 2>/dev/null; then
    echo "❌ Nginx config test failed - aborting"
    exit 1
fi

# Reload nginx without downtime
systemctl reload nginx

echo ""
echo "✅ Switched to ${TARGET^^} ($TARGET_IP:$PORT)"
echo "   Previous: ${CURRENT} (now inactive - kept as fallback)"
echo ""
echo "📋 Monitor with:"
echo "   curl http://localhost/api/health"
echo "   tail -f /var/log/nginx/access.log"
echo ""
echo "↩️  To rollback run:"
echo "   sudo /opt/scripts/switch-backend.sh $([ "$TARGET" = "green" ] && echo "blue" || echo "green")"
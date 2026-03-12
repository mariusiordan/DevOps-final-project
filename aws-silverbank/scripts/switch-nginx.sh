#!/bin/bash
# Blue/Green traffic switch
# Usage: ./switch-nginx.sh blue|green

TARGET=$1
UPSTREAM_CONFIG="/etc/nginx/conf.d/upstream.conf"

if [ "$TARGET" != "blue" ] && [ "$TARGET" != "green" ]; then
  echo "Usage: $0 blue|green"
  exit 1
fi

BLUE_IP="${BLUE_IP:-10.0.2.110}"
GREEN_IP="${GREEN_IP:-10.0.2.40}"

if [ "$TARGET" == "blue" ]; then
  ACTIVE_IP=$BLUE_IP
else
  ACTIVE_IP=$GREEN_IP
fi

echo "Switching traffic to $TARGET ($ACTIVE_IP)..."

cat > $UPSTREAM_CONFIG << NGINX
upstream silverbank_active {
  server $ACTIVE_IP:3000;
}
NGINX

nginx -t && systemctl reload nginx

if [ $? -eq 0 ]; then
  echo "✅ Traffic switched to $TARGET successfully!"
  echo $TARGET > /opt/current-env
  echo "[$TARGET] $(date)" >> /var/log/nginx/switches.log
else
  echo "❌ Nginx reload failed! Rolling back..."
  exit 1
fi

#!/bin/bash
# Blue/Green traffic switch
# Usage: ./switch-nginx.sh blue|green

TARGET=$1
NGINX_CONFIG="/etc/nginx/sites-available/silverbank"

if [ "$TARGET" != "blue" ] && [ "$TARGET" != "green" ]; then
  echo "Usage: $0 blue|green"
  exit 1
fi

BLUE_IP="${BLUE_IP:-10.0.1.10}"
GREEN_IP="${GREEN_IP:-10.0.1.11}"

if [ "$TARGET" == "blue" ]; then
  ACTIVE_IP=$BLUE_IP
else
  ACTIVE_IP=$GREEN_IP
fi

echo "Switching traffic to $TARGET ($ACTIVE_IP)..."

cat > $NGINX_CONFIG << EOF
upstream silverbank_active {
  server $ACTIVE_IP:3000;
}

server {
  listen 80;
  server_name _;

  location / {
    proxy_pass http://silverbank_active;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
  }

  location /api/health {
    proxy_pass http://silverbank_active/api/health;
  }
}
EOF

nginx -t && systemctl reload nginx

if [ $? -eq 0 ]; then
  echo "✅ Traffic switched to $TARGET successfully!"
  echo $TARGET > /opt/current-env
else
  echo "❌ Nginx reload failed! Rolling back..."
  exit 1
fi
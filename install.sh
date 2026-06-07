#!/bin/bash
set -e

echo "=== 3x-ui + Nginx + Certbot installer ==="

read -p "Введите домен, например panel.example.com: " DOMAIN

if [ -z "$DOMAIN" ]; then
  echo "Ошибка: домен не указан"
  exit 1
fi

echo "Используем домен: $DOMAIN"

echo "=== 1. Update server ==="
apt update && apt upgrade -y

echo "=== 2. Install Nginx and Certbot ==="
apt install nginx certbot python3-certbot-nginx curl wget socat ufw -y

echo "=== 3. Remove default Nginx site ==="
rm -f /etc/nginx/sites-enabled/default

echo "=== 4. Create site directory ==="
mkdir -p /var/www/html/site

cat > /var/www/html/site/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>$DOMAIN</title>
</head>
<body>
  <h1>OK</h1>
</body>
</html>
EOF

echo "=== 5. Create temporary HTTP Nginx config ==="
cat > /etc/nginx/sites-available/sni.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    if (\$host = $DOMAIN) {
        return 301 https://\$host\$request_uri;
    }

    return 404;
}
EOF

ln -sf /etc/nginx/sites-available/sni.conf /etc/nginx/sites-enabled/sni.conf

nginx -t
systemctl restart nginx

echo "=== 6. Issue SSL certificate ==="
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m admin@$DOMAIN --redirect

echo "=== 7. Create final Reality-compatible Nginx config ==="
cat > /etc/nginx/sites-available/sni.conf <<EOF
server {
    listen 127.0.0.1:9000 ssl http2 proxy_protocol;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_session_cache shared:SSL:1m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    real_ip_header proxy_protocol;
    set_real_ip_from 127.0.0.1;
    set_real_ip_from ::1;

    root /var/www/html/site;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

nginx -t
systemctl restart nginx

echo "=== 8. Install 3x-ui ==="
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

echo "=== DONE ==="
echo "Домен: $DOMAIN"
echo "Nginx SNI fallback слушает: 127.0.0.1:9000"
echo "Теперь в 3x-ui Reality dest указывай: 127.0.0.1:9000"
echo "serverNames/SNI: $DOMAIN"

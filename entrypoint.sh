#!/bin/bash

set -euo pipefail

# Validate environment variables
: "${PUBLIC_HOST:?Set PUBLIC_HOST using --env}"
: "${SERVER1:?Set SERVER1 using --env}"
: "${SERVER2:?Set SERVER2 using --env}"
: "${SECRET_TOKEN:?Set SECRET_TOKEN using --env}"

echo ">> generating self signed cert"
openssl req -x509 -newkey rsa:4086 \
-subj "/C=XX/ST=XXXX/L=XXXX/O=XXXX/CN=localhost" \
-keyout "/key.pem" \
-out "/cert.pem" \
-days 3650 -nodes -sha256

cat <<EOF >/etc/nginx/nginx.conf
user nginx;
worker_processes 2;
events {
  worker_connections 1024;
}

http {
  upstream upstream_server{
      server ${SERVER1} max_fails=3 fail_timeout=30s;
      server ${SERVER2} max_fails=3 fail_timeout=30s;
  }
  access_log /var/log/nginx/access.log;
  error_log /var/log/nginx/error.log;
  server_tokens off;
  server {
    listen 443 ssl;
    server_name localhost;

    ssl_certificate /cert.pem;
    ssl_certificate_key /key.pem;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    
    include /etc/nginx/mime.types;
    real_ip_header X-Forwarded-For;
    real_ip_recursive on;
    set_real_ip_from 172.16.0.0/20;
    set_real_ip_from 10.0.0.0/8;
    set_real_ip_from 192.168.0.0/16;
    client_max_body_size 600M;
  
    location / {
        proxy_pass https://upstream_server;
        proxy_set_header Host ${PUBLIC_HOST};
        proxy_set_header CDN_SECRET ${SECRET_TOKEN};
    } 
  }
}
EOF

echo "Running nginx..."

# Launch nginx in the foreground
/usr/sbin/nginx -g "daemon off;"

#!/bin/bash

set -euo pipefail

# Validate environment variables
#: "${PUBLIC_HOST:?Set PUBLIC_HOST using --env}"
#: "${SERVER:?Set SERVER using --env}"
#: "${SECRET_TOKEN:?Set SECRET_TOKEN using --env}"
: "${SERVER:?Set SERVER using --env}"

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
      server ${SERVER};
  }


  log_format main '\$http_x_forwarded_for - \$remote_user [\$time_local] '
                  '"\$request" \$status \$body_bytes_sent "\$http_referer" '
                  '"\$http_user_agent"' ;

  access_log /var/log/nginx/access.log main;
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
        proxy_set_header Host \$host;
        proxy_set_header x-forwarded-for \$proxy_add_x_forwarded_for;
        proxy_pass http://upstream_server;
    } 
  }
}
EOF

echo "Running nginx..."

# Launch nginx in the foreground
/usr/sbin/nginx -g "daemon off;"

FROM debian:bookworm-slim

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    nginx \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

## Download and install cleoselene
# RUN curl -fsSL https://cleoselene.com/downloads/cleoselene-linux -o /usr/local/bin/cleoselene \
#     && chmod +x /usr/local/bin/cleoselene

# Create app directory
WORKDIR /app

# Copy game files
COPY proximity_game.lua .
COPY npc.lua .
COPY index.html /var/www/html/index.html

# Copy custom client
COPY client/ ./client/

# Custom cleoselene engine
COPY cleoselene /usr/local/bin/cleoselene

# Rewrite iframe URL for Docker (localhost:3425 -> /game/)
RUN sed -i 's|http://localhost:3425|/game/|g' /var/www/html/index.html

# Nginx config
RUN cat <<'EOF' > /etc/nginx/sites-available/default
server {
    listen 8080;
    server_name _;
    root /var/www/html;
    index index.html;

    location / {
        try_files $uri /index.html;
    }

    location /game/ {
        rewrite ^/game/(.*) /$1 break;
        proxy_pass http://127.0.0.1:3425;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # WebSocket at /ws (direct)
    location /ws {
        proxy_pass http://127.0.0.1:3425/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
EOF

# Supervisor config
RUN cat <<'EOF' > /etc/supervisor/supervisord.conf
[supervisord]
nodaemon=true
user=root

[program:nginx]
command=nginx -g "daemon off;"

[program:cleoselene]
command=/usr/local/bin/cleoselene --client /app/client /app/proximity_game.lua
directory=/app

EOF

# Expose nginx port
EXPOSE 8080

# Run supervisor
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]

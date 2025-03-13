#!/bin/bash

set -e  # Exit immediately if any command fails
export DEBIAN_FRONTEND=noninteractive

# Variables
GITHUB_REPO="unforkableco/blockscout_substr"
EXPLORER_DIR="/opt/blockscout"
# RPC_URL=$1 injected by github actions
DOMAIN_NAME=$2  # Add domain name as second argument

# Ensure RPC URL is provided
if [ -z "$RPC_URL" ]; then
  echo "❌ ERROR: RPC URL is required as the first argument!"
  exit 1
fi

echo "🚀 Starting Blockscout Setup..."
echo "🔗 Using RPC URL: $RPC_URL"

# Check if domain name is provided for HTTPS setup
if [ -n "$DOMAIN_NAME" ]; then
  echo "🔒 HTTPS will be set up for domain: $DOMAIN_NAME"
  ENABLE_HTTPS=true
else
  echo "⚠️ No domain provided. HTTPS will not be configured."
  ENABLE_HTTPS=false
fi

# Update system packages
echo "🔄 Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install dependencies
echo "📦 Installing dependencies..."
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common git

# Add Docker's official GPG key & repository
echo "🔑 Adding Docker repository..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# Install Docker and Docker Compose
echo "🐳 Installing Docker and Docker Compose..."
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Verify Docker installation
echo "🔍 Verifying Docker installation..."
if ! command -v docker &> /dev/null; then
    echo "❌ Docker installation failed!"
    exit 1
fi

if ! command -v docker compose &> /dev/null; then
    echo "❌ Docker Compose installation failed!"
    exit 1
fi

docker --version
docker compose version

# Ensure Docker service is running
echo "🐳 Ensuring Docker is running..."
sudo systemctl enable --now docker
sudo systemctl status docker --no-pager

# **Ensure the 'ubuntu' user can run Docker without sudo**
echo "👤 Adding ubuntu user to docker group..."
sudo usermod -aG docker ubuntu
newgrp docker

# Clone Blockscout repository
echo "⬇️ Fetching Blockscout repository..."
sudo mkdir -p $EXPLORER_DIR
sudo chown ubuntu:ubuntu $EXPLORER_DIR
git clone https://github.com/$GITHUB_REPO.git $EXPLORER_DIR || (cd $EXPLORER_DIR && git pull)

# Move to Blockscout directory
cd $EXPLORER_DIR/docker-compose

# Get chain ID from RPC endpoint
echo "🔍 Detecting chain ID from RPC endpoint..."
CHAIN_ID_HEX=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' http://$RPC_URL | grep -o '"result":"0x[^"]*"' | cut -d'"' -f4 | sed 's/0x//')
if [ -n "$CHAIN_ID_HEX" ]; then
  CHAIN_ID=$((16#$CHAIN_ID_HEX))
  echo "✅ Detected chain ID: $CHAIN_ID"
else
  CHAIN_ID=42
  echo "⚠️ Could not detect chain ID, using default: $CHAIN_ID"
fi

# Get server IP address
SERVER_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
if [ -z "$SERVER_IP" ]; then
  echo "⚠️ Could not detect server IP, using localhost"
  SERVER_IP="localhost"
else
  echo "🌐 Server IP address: $SERVER_IP"
fi

# Set protocol based on HTTPS configuration
if [ "$ENABLE_HTTPS" = true ]; then
  PROTOCOL="https"
  APP_HOST="$DOMAIN_NAME"
else
  PROTOCOL="http"
  APP_HOST="$SERVER_IP"
fi

# Create `.env` configuration
echo "⚙️ Creating environment configuration..."
cat > .env << EOF
ETHEREUM_JSONRPC_HTTP_URL=http://$RPC_URL
ETHEREUM_JSONRPC_TRACE_URL=http://$RPC_URL
ETHEREUM_JSONRPC_WS_URL=ws://$RPC_URL
NETWORK=custom
SUBNETWORK=pos
BLOCK_TRANSFORMER=base
INDEXER_DISABLE_NFT_FETCHER=true
NFT_MEDIA_HANDLER_ENABLED=false
ETHEREUM_JSONRPC_VARIANT=geth
CHAIN_ID=$CHAIN_ID
EOF

# Create frontend environment configuration
echo "⚙️ Creating frontend environment configuration..."
cat > ./envs/common-frontend.env << EOF
NEXT_PUBLIC_API_HOST=$APP_HOST
NEXT_PUBLIC_API_PROTOCOL=$PROTOCOL
NEXT_PUBLIC_STATS_API_HOST=$PROTOCOL://$APP_HOST:8080
NEXT_PUBLIC_NETWORK_NAME=Custom Network
NEXT_PUBLIC_NETWORK_SHORT_NAME=Custom
NEXT_PUBLIC_NETWORK_ID=$CHAIN_ID
NEXT_PUBLIC_NETWORK_CURRENCY_NAME=Ether
NEXT_PUBLIC_NETWORK_CURRENCY_SYMBOL=ETH
NEXT_PUBLIC_NETWORK_CURRENCY_DECIMALS=18
NEXT_PUBLIC_API_BASE_PATH=/
NEXT_PUBLIC_APP_HOST=$APP_HOST
NEXT_PUBLIC_APP_PROTOCOL=$PROTOCOL
NEXT_PUBLIC_HOMEPAGE_CHARTS=['daily_txs']
NEXT_PUBLIC_VISUALIZE_API_HOST=$PROTOCOL://$APP_HOST:8081
NEXT_PUBLIC_IS_TESTNET=true
NEXT_PUBLIC_API_WEBSOCKET_PROTOCOL=ws
NEXT_PUBLIC_API_SPEC_URL=https://raw.githubusercontent.com/blockscout/blockscout-api-v2-swagger/main/swagger.yaml
NEXT_PUBLIC_NETWORK_RPC_URL=http://$RPC_URL
EOF

# Fix CORS configuration in nginx templates
echo "⚙️ Fixing CORS configuration in nginx templates..."
if [ "$ENABLE_HTTPS" = true ]; then
  sed -i "s|http://localhost:3000|https://$DOMAIN_NAME|g" ./proxy/microservices.conf.template
  sed -i "s|http://localhost|https://$DOMAIN_NAME|g" ./proxy/default.conf.template
else
  sed -i "s|http://localhost:3000|http://$SERVER_IP|g" ./proxy/microservices.conf.template
  sed -i "s|http://localhost|http://$SERVER_IP|g" ./proxy/default.conf.template
fi

# If HTTPS is enabled, create SSL configuration for Nginx
if [ "$ENABLE_HTTPS" = true ]; then
  echo "🔒 Setting up HTTPS with Let's Encrypt..."
  
  # Install Certbot
  sudo apt install -y certbot python3-certbot-nginx
  
  # Create Nginx SSL configuration template
  cat > ./proxy/ssl.conf.template << EOF
map \$http_upgrade \$connection_upgrade {
  default upgrade;
  ''      close;
}

server {
    listen 80;
    server_name $DOMAIN_NAME;
    
    # Redirect all HTTP requests to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name $DOMAIN_NAME;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_stapling on;
    ssl_stapling_verify on;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-XSS-Protection "1; mode=block";
    
    location ~ ^/(api(?!-docs\$)|socket|sitemap.xml|auth/auth0|auth/auth0/callback|auth/logout) {
        proxy_pass            \${BACK_PROXY_PASS};
        proxy_http_version    1.1;
        proxy_set_header      Host "\$host";
        proxy_set_header      X-Real-IP "\$remote_addr";
        proxy_set_header      X-Forwarded-For "\$proxy_add_x_forwarded_for";
        proxy_set_header      X-Forwarded-Proto "\$scheme";
        proxy_set_header      Upgrade "\$http_upgrade";
        proxy_set_header      Connection \$connection_upgrade;
        proxy_cache_bypass    \$http_upgrade;
    }
    
    location / {
        proxy_pass            \${FRONT_PROXY_PASS};
        proxy_http_version    1.1;
        proxy_set_header      Host "\$host";
        proxy_set_header      X-Real-IP "\$remote_addr";
        proxy_set_header      X-Forwarded-For "\$proxy_add_x_forwarded_for";
        proxy_set_header      X-Forwarded-Proto "\$scheme";
        proxy_set_header      Upgrade "\$http_upgrade";
        proxy_set_header      Connection \$connection_upgrade;
        proxy_cache_bypass    \$http_upgrade;
    }
}

server {
    listen 8080 ssl;
    server_name $DOMAIN_NAME;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem;
    
    proxy_http_version 1.1;
    proxy_hide_header Access-Control-Allow-Origin;
    proxy_hide_header Access-Control-Allow-Methods;
    add_header 'Access-Control-Allow-Origin' 'https://$DOMAIN_NAME' always;
    add_header 'Access-Control-Allow-Credentials' 'true' always;
    add_header 'Access-Control-Allow-Methods' 'PUT, GET, POST, OPTIONS, DELETE, PATCH' always;
    
    location / {
        proxy_pass            http://stats:8050/;
        proxy_http_version    1.1;
        proxy_set_header      Host "\$host";
        proxy_set_header      X-Real-IP "\$remote_addr";
        proxy_set_header      X-Forwarded-For "\$proxy_add_x_forwarded_for";
        proxy_set_header      X-Forwarded-Proto "\$scheme";
        proxy_set_header      Upgrade "\$http_upgrade";
        proxy_set_header      Connection \$connection_upgrade;
        proxy_cache_bypass    \$http_upgrade;
    }
}

server {
    listen 8081 ssl;
    server_name $DOMAIN_NAME;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem;
    
    proxy_http_version 1.1;
    proxy_hide_header Access-Control-Allow-Origin;
    proxy_hide_header Access-Control-Allow-Methods;
    add_header 'Access-Control-Allow-Origin' 'https://$DOMAIN_NAME' always;
    add_header 'Access-Control-Allow-Credentials' 'true' always;
    add_header 'Access-Control-Allow-Methods' 'PUT, GET, POST, OPTIONS, DELETE, PATCH' always;
    add_header 'Access-Control-Allow-Headers' 'DNT,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization,x-csrf-token' always;
    
    location / {
        proxy_pass            http://visualizer:8050/;
        proxy_http_version    1.1;
        proxy_buffering       off;
        proxy_set_header      Host "\$host";
        proxy_set_header      X-Real-IP "\$remote_addr";
        proxy_set_header      X-Forwarded-For "\$proxy_add_x_forwarded_for";
        proxy_set_header      X-Forwarded-Proto "\$scheme";
        proxy_set_header      Upgrade "\$http_upgrade";
        proxy_set_header      Connection \$connection_upgrade;
        proxy_cache_bypass    \$http_upgrade;
        if (\$request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' 'https://$DOMAIN_NAME' always;
            add_header 'Access-Control-Allow-Credentials' 'true' always;
            add_header 'Access-Control-Allow-Methods' 'PUT, GET, POST, OPTIONS, DELETE, PATCH' always;
            add_header 'Access-Control-Allow-Headers' 'DNT,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization,x-csrf-token' always;
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain charset=UTF-8';
            add_header 'Content-Length' 0;
            return 204;
        }
    }
}
EOF

  # Update the nginx service to use the SSL configuration
  sed -i 's|../proxy:/etc/nginx/templates|../proxy:/etc/nginx/templates|g' ./services/nginx.yml
  
  # Modify docker-compose to expose port 443
  sed -i '/- target: 80/a\      - target: 443\n        published: 443' ./services/nginx.yml
fi

# Create a systemd service for Blockscout
echo "⚙️ Creating systemd service for Blockscout..."
sudo tee /etc/systemd/system/blockscout.service > /dev/null <<EOF
[Unit]
Description=Blockscout Explorer
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=$EXPLORER_DIR/docker-compose
ExecStart=/usr/bin/docker compose up --force-recreate
ExecStop=/usr/bin/docker compose down
Restart=always
RestartSec=10
User=ubuntu
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Set permissions for Blockscout directory
sudo chown -R ubuntu:ubuntu /opt/blockscout
sudo chmod -R 755 /opt/blockscout

# If HTTPS is enabled, obtain SSL certificate before starting services
if [ "$ENABLE_HTTPS" = true ]; then
  echo "🔒 Obtaining SSL certificate from Let's Encrypt..."
  
  # Start a temporary Nginx server for certificate validation
  sudo apt install -y nginx
  sudo tee /etc/nginx/sites-available/default > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;
    root /var/www/html;
    location ~ /.well-known {
        allow all;
    }
}
EOF
  sudo systemctl restart nginx
  
  # Obtain SSL certificate
  sudo certbot certonly --nginx -d $DOMAIN_NAME --non-interactive --agree-tos --email admin@$DOMAIN_NAME
  
  # Stop temporary Nginx
  sudo systemctl stop nginx
  
  # Copy SSL configuration to be used by the proxy container
  cp ./proxy/ssl.conf.template ./proxy/default.conf.template
  
  # Create Docker volume for Let's Encrypt certificates
  docker volume create --name=letsencrypt
  
  # Update nginx service to mount the certificates
  sed -i '/volumes:/a\      - /etc/letsencrypt:/etc/letsencrypt:ro' ./services/nginx.yml
fi

# Enable and start Blockscout service
echo "🚀 Enabling and starting Blockscout service..."
sudo systemctl daemon-reload
sudo systemctl enable blockscout
sudo systemctl start blockscout

# Wait for service to start and verify it's running
echo "⏳ Waiting for service to start..."
sleep 30
sudo systemctl status blockscout --no-pager

# Verify and fix CORS configuration in running container
echo "⚙️ Verifying CORS configuration in running container..."
if [ "$ENABLE_HTTPS" = true ]; then
  docker exec proxy sed -i "s|http://localhost|https://$DOMAIN_NAME|g" /etc/nginx/conf.d/default.conf
else
  docker exec proxy sed -i "s|http://localhost|http://$SERVER_IP|g" /etc/nginx/conf.d/default.conf
fi
docker exec proxy nginx -s reload

# Set up automatic certificate renewal if HTTPS is enabled
if [ "$ENABLE_HTTPS" = true ]; then
  echo "🔄 Setting up automatic certificate renewal..."
  sudo tee /etc/cron.d/certbot > /dev/null <<EOF
0 */12 * * * root certbot renew --quiet --post-hook "docker exec proxy nginx -s reload"
EOF
  sudo chmod 644 /etc/cron.d/certbot
fi

echo "✅ Blockscout setup complete!"
if [ "$ENABLE_HTTPS" = true ]; then
  echo "🔒 Access the explorer securely at https://$DOMAIN_NAME"
else
  echo "🌐 Access the explorer at http://$SERVER_IP"
fi

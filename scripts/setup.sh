#!/bin/bash

set -e  # Exit immediately if any command fails
export DEBIAN_FRONTEND=noninteractive

# Variables
GITHUB_REPO="unforkableco/blockscout_substr"
EXPLORER_DIR="/opt/blockscout"
# RPC_URL=$1 injected by github actions

# Ensure RPC URL is provided
if [ -z "$RPC_URL" ]; then
  echo "❌ ERROR: RPC URL is required as the first argument!"
  exit 1
fi

echo "🚀 Starting Blockscout Setup..."
echo "🔗 Using RPC URL: $RPC_URL"

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
echo "🌐 Server IP address: $SERVER_IP"

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
NEXT_PUBLIC_API_HOST=$SERVER_IP
NEXT_PUBLIC_API_PROTOCOL=http
NEXT_PUBLIC_STATS_API_HOST=http://$SERVER_IP:8080
NEXT_PUBLIC_NETWORK_NAME=Custom Network
NEXT_PUBLIC_NETWORK_SHORT_NAME=Custom
NEXT_PUBLIC_NETWORK_ID=$CHAIN_ID
NEXT_PUBLIC_NETWORK_CURRENCY_NAME=Ether
NEXT_PUBLIC_NETWORK_CURRENCY_SYMBOL=ETH
NEXT_PUBLIC_NETWORK_CURRENCY_DECIMALS=18
NEXT_PUBLIC_API_BASE_PATH=/
NEXT_PUBLIC_APP_HOST=$SERVER_IP
NEXT_PUBLIC_APP_PROTOCOL=http
NEXT_PUBLIC_HOMEPAGE_CHARTS=['daily_txs']
NEXT_PUBLIC_VISUALIZE_API_HOST=http://$SERVER_IP:8081
NEXT_PUBLIC_IS_TESTNET=true
NEXT_PUBLIC_API_WEBSOCKET_PROTOCOL=ws
NEXT_PUBLIC_API_SPEC_URL=https://raw.githubusercontent.com/blockscout/blockscout-api-v2-swagger/main/swagger.yaml
NEXT_PUBLIC_NETWORK_RPC_URL=http://$RPC_URL
EOF

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

# Enable and start Blockscout service
echo "🚀 Enabling and starting Blockscout service..."
sudo systemctl daemon-reload
sudo systemctl enable blockscout
sudo systemctl start blockscout

# Wait for service to start and verify it's running
echo "⏳ Waiting for service to start..."
sleep 30
sudo systemctl status blockscout --no-pager

echo "✅ Blockscout setup complete!"
echo "🌐 Access the explorer at http://$SERVER_IP"

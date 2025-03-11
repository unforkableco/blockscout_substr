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
sudo apt install -y curl git jq tmux systemd docker.io docker-compose

# Ensure Docker service is running
echo "🐳 Ensuring Docker is running..."
sudo systemctl enable --now docker

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

# Create `.env` configuration
echo "⚙️ Creating environment configuration..."
cat <<EOF > .env
ETHEREUM_JSONRPC_HTTP_URL=http://$RPC_URL
ETHEREUM_JSONRPC_TRACE_URL=http://$RPC_URL
ETHEREUM_JSONRPC_WS_URL=ws://$RPC_URL
NETWORK=custom
SUBNETWORK=pos
BLOCK_TRANSFORMER=clique
INDEXER_DISABLE_NFT_FETCHER=true
NFT_MEDIA_HANDLER_ENABLED=false
ETHEREUM_JSONRPC_VARIANT=geth
CHAIN_ID=1666
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
ExecStart=/usr/bin/docker-compose up --force-recreate
ExecStop=/usr/bin/docker-compose down
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

# Enable and start Blockscout as a systemd service
echo "🚀 Enabling and starting Blockscout service..."
sudo systemctl daemon-reload
sudo systemctl enable blockscout
sudo systemctl start blockscout

echo "✅ Blockscout setup complete!"

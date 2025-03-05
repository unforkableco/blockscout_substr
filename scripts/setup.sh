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
DATABASE_URL=postgresql://postgres:postgres@postgres:5432/blockscout
ETHEREUM_JSONRPC_HTTP_URL=$RPC_URL
ETHEREUM_JSONRPC_TRACE_URL=$RPC_URL
ETHEREUM_JSONRPC_WS_URL=$RPC_URL
NETWORK=custom
SUBNETWORK=pos
BLOCK_TRANSFORMER=sub
INDEXER_DISABLE_NFT_FETCHER=true
EOF

# Start Blockscout using Docker Compose
echo "🐳 Running Blockscout with Docker Compose..."
sudo docker compose up -d --build
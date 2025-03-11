#!/bin/bash

set -e  # Exit immediately if any command fails

# Variables
CONTAINER_NAME="blockscout-test"
EXPLORER_DIR="/opt/blockscout"
RPC_URL=${1:-"3.81.186.31:9944"}  # Use provided RPC URL or default

echo "🚀 Starting Blockscout Test Deployment..."
echo "🔗 Using RPC URL: $RPC_URL"

# Create and run the test container
docker run -d \
  --name $CONTAINER_NAME \
  --privileged \
  -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
  -p 80:80 \
  -p 8080:8080 \
  -p 8081:8081 \
  -p 4000:4000 \
  blockscout-test

# Wait for systemd to start
echo "⏳ Waiting for container to start..."
sleep 5

# Install Docker and set up Blockscout inside container
docker exec -it $CONTAINER_NAME bash -c "
# Install Docker
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository 'deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable'
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Start Docker service
systemctl start docker

# Clone Blockscout repository
mkdir -p $EXPLORER_DIR
cd $EXPLORER_DIR
git clone https://github.com/unforkableco/blockscout_substr.git .
cd docker-compose

# Create environment configuration
cat > .env << EOF
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

# Start services
docker compose up -d
"

echo "✅ Blockscout test deployment complete!"
echo "🌐 Access the explorer at http://localhost:80" 
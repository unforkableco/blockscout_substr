#!/bin/bash

# Exit on error
set -e

# Check if RPC_URL is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <rpc_url>"
    echo "Example: $0 3.81.186.31:9944"
    exit 1
fi

RPC_URL=$1

# Clean up any existing container
echo "🧹 Cleaning up any existing test container..."
docker rm -f blockscout-test 2>/dev/null || true

echo "🔨 Building test environment..."
docker build -t blockscout-test -f Dockerfile.test .

echo "🚀 Running test environment..."
docker run --privileged \
    --cgroupns=host \
    -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e RPC_URL="$RPC_URL" \
    -p 4000:4000 \
    -d \
    --name blockscout-test \
    blockscout-test

# Wait for container to be running
echo "⏳ Waiting for container to start..."
sleep 5

# Check container status
if ! docker ps | grep -q blockscout-test; then
    echo "❌ Container failed to start. Logs:"
    docker logs blockscout-test
    exit 1
fi

echo "📝 Following setup logs..."
docker exec blockscout-test bash -c "RPC_URL=$RPC_URL /setup.sh"

echo "✅ Setup complete! Blockscout should be accessible at http://localhost:4000"
echo "To view logs: docker logs -f blockscout-test"
echo "To stop: docker rm -f blockscout-test" 
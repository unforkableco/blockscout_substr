#!/bin/bash

# Check if required arguments are provided
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <rpc_url> <domain_name> [ssh_key_path]"
    echo "Example: $0 3.81.186.31:9944 explorer.example.com ~/my-key.pem"
    exit 1
fi

RPC_URL=$1
DOMAIN_NAME=$2
SSH_KEY=${3:-""}

# Generate a unique identifier for this deployment
DEPLOY_ID=$(date +%s)

echo "🚀 Starting Blockscout deployment with HTTPS..."
echo "🔗 RPC URL: $RPC_URL"
echo "🔒 Domain: $DOMAIN_NAME"
echo "🔑 SSH Key: ${SSH_KEY:-"Using default SSH key"}"
echo "🆔 Deployment ID: $DEPLOY_ID"

# Check if domain DNS is properly configured
echo "🔍 Checking DNS configuration for $DOMAIN_NAME..."
DOMAIN_IP=$(dig +short $DOMAIN_NAME)
if [ -z "$DOMAIN_IP" ]; then
    echo "❌ ERROR: Domain $DOMAIN_NAME is not configured in DNS!"
    echo "Please set up an A record pointing to your EC2 instance's IP address."
    exit 1
else
    echo "✅ Domain $DOMAIN_NAME resolves to IP: $DOMAIN_IP"
fi

# Deploy to EC2 instance
if [ -n "$SSH_KEY" ]; then
    # If SSH key is provided, use it
    echo "🔄 Deploying to EC2 instance using provided SSH key..."
    ssh -i "$SSH_KEY" ubuntu@$DOMAIN_IP "curl -s https://raw.githubusercontent.com/unforkableco/blockscout_substr/master/scripts/setup.sh > setup.sh && chmod +x setup.sh && ./setup.sh $RPC_URL $DOMAIN_NAME"
else
    # Otherwise, use the default SSH configuration
    echo "🔄 Deploying to EC2 instance using default SSH configuration..."
    ssh ubuntu@$DOMAIN_IP "curl -s https://raw.githubusercontent.com/unforkableco/blockscout_substr/master/scripts/setup.sh > setup.sh && chmod +x setup.sh && ./setup.sh $RPC_URL $DOMAIN_NAME"
fi

echo "✅ Deployment completed!"
echo "🌐 Your Blockscout explorer should be available at https://$DOMAIN_NAME once DNS propagation is complete."
echo "⏱️ Note: It may take a few minutes for the SSL certificate to be issued and for all services to start."
echo "🔍 To check the status, you can run: ssh ${SSH_KEY:+"-i $SSH_KEY "}ubuntu@$DOMAIN_IP \"sudo systemctl status blockscout\"" 
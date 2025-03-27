#!/bin/bash

set -euo pipefail

echo "✅ Starting Seismic Devnet Deployment..."

# Detect OS
OS=$(uname -s)
echo "✅ Detected OS: $OS"

# Install Rust if not installed
if ! command -v rustc &>/dev/null; then
    echo "🔍 Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    echo "✅ Rust installed."
else
    echo "✅ Rust is already installed."
fi

# Install jq based on OS
echo "🔍 Installing jq..."
case "$OS" in
    "Linux") sudo apt-get update && sudo apt-get install -y jq ;;
    "Darwin") brew install jq ;;
    *) echo "❌ Unsupported OS: $OS" && exit 1 ;;
esac
echo "✅ jq installed."

# Install Seismic Foundry tools
if ! command -v sfoundryup &>/dev/null; then
    echo "🔍 Installing Seismic Foundry tools..."
    curl -L -H "Accept: application/vnd.github.v3.raw" \
         "https://api.github.com/repos/SeismicSystems/seismic-foundry/contents/sfoundryup/install?ref=seismic" | bash
    source ~/.bashrc || source ~/.zshrc || true
    sfoundryup
    echo "✅ Seismic Foundry tools installed."
else
    echo "✅ Seismic Foundry tools are already installed."
fi

# Clone the try-devnet repo if not exists
if [ ! -d "try-devnet" ]; then
    echo "🔍 Cloning Seismic try-devnet repository..."
    git clone --recurse-submodules https://github.com/SeismicSystems/try-devnet.git
fi

cd try-devnet/packages/contract/

# Deploy the first contract
echo "🚀 Deploying first contract..."
DEPLOY_OUTPUT=$(bash script/deploy.sh)

# Extract deployed address
CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -oE '0x[a-fA-F0-9]{40}' | head -n 1)

if [ -z "$CONTRACT_ADDRESS" ]; then
    echo "❌ Error: Could not extract deployed contract address."
    exit 1
fi

echo "✅ First contract deployed: $CONTRACT_ADDRESS"

# Pause for faucet request
echo "⚠️ Visit the faucet and enter the contract address below to request funds:"
echo "➡️ Faucet: https://faucet-2.seismicdev.net/"
echo "🔹 Address: $CONTRACT_ADDRESS"
read -p "Press Enter after funding the wallet..."

# Ensure we're in the right directory for the second deployment
cd ../../

# Deploy the second contract from try-devnet
echo "🚀 Deploying second contract from try-devnet..."
cd packages/contract/
if [ -f "script/deploy.sh" ]; then
    DEPLOY_OUTPUT=$(bash script/deploy.sh)
    CONTRACT_ADDRESS_2=$(echo "$DEPLOY_OUTPUT" | grep -oE '0x[a-fA-F0-9]{40}' | head -n 1)

    if [ -z "$CONTRACT_ADDRESS_2" ]; then
        echo "❌ Error: Could not extract deployed contract address for the second contract."
        exit 1
    fi

    echo "✅ Second contract deployed: $CONTRACT_ADDRESS_2"
else
    echo "❌ Error: Second contract deploy script not found!"
    exit 1
fi

# Pause for faucet request before proceeding to interaction
echo "⚠️ Visit the faucet again and enter the second contract address:"
echo "➡️ Faucet: https://faucet-2.seismicdev.net/"
echo "🔹 Address: $CONTRACT_ADDRESS_2"
read -p "Press Enter after funding the wallet..."

# Install Bun for interaction
if ! command -v bun &>/dev/null; then
    echo "🔍 Installing Bun..."
    curl -fsSL https://bun.sh/install | bash
    source ~/.bashrc || source ~/.zshrc || true
    echo "✅ Bun installed."
else
    echo "✅ Bun is already installed."
fi

# Install CLI dependencies and interact with contract
cd ../cli/
echo "🔍 Installing CLI dependencies..."
bun install

echo "🚀 Running transaction script..."
bash script/transact.sh

echo "🎉 Deployment and interaction complete! You did a good job!"

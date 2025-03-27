#!/bin/bash

echo "✅ Starting Seismic Devnet Deployment..."

# Detect OS
OS=$(uname -s)
echo "✅ Detected OS: $OS"

# Install Rust if not installed
if ! command -v rustc &> /dev/null; then
    echo "🔍 Installing Rust..."
    curl https://sh.rustup.rs -sSf | sh -s -- -y
    source "$HOME/.cargo/env"
else
    echo "✅ Rust is already installed."
fi

# Install jq
if ! command -v jq &> /dev/null; then
    echo "🔍 Installing jq..."
    if [[ "$OS" == "Linux" ]]; then
        sudo apt install -y jq
    elif [[ "$OS" == "Darwin" ]]; then
        brew install jq
    fi
else
    echo "✅ jq is already installed."
fi

# Set Seismic Foundry installation directory
SEISMIC_BIN="$HOME/.seismic/bin"
mkdir -p "$SEISMIC_BIN"

# Install sfoundryup
echo "🔍 Installing sfoundryup..."
curl -L -H "Accept: application/vnd.github.v3.raw" \
     "https://api.github.com/repos/SeismicSystems/seismic-foundry/contents/sfoundryup/install?ref=seismic" | bash

# Ensure PATH is updated
export PATH="$HOME/.seismic/bin:$PATH"
echo 'export PATH="$HOME/.seismic/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Verify sfoundryup installation
if [ ! -f "$HOME/.seismic/bin/sfoundryup" ]; then
    echo "❌ sfoundryup installation failed. Exiting."
    exit 1
fi

# Run sfoundryup to install Seismic Foundry tools
echo "🚀 Running sfoundryup to install sfoundry..."
"$HOME/.seismic/bin/sfoundryup"

# Check if sfoundry is installed
if ! command -v sfoundry &> /dev/null; then
    echo "❌ sfoundry installation failed. Retrying clean install..."
    
    # REINSTALL SFOUNDRYUP BEFORE TRYING AGAIN
    curl -L -H "Accept: application/vnd.github.v3.raw" \
         "https://api.github.com/repos/SeismicSystems/seismic-foundry/contents/sfoundryup/install?ref=seismic" | bash
    export PATH="$HOME/.seismic/bin:$PATH"
    source ~/.bashrc

    # Retry sfoundryup
    "$HOME/.seismic/bin/sfoundryup"
fi

# Final verification
if ! command -v sfoundry &> /dev/null; then
    echo "❌ sfoundry installation still failed. Exiting."
    exit 1
else
    echo "✅ sfoundry installed successfully."
fi

# Clone the repository if not already cloned
if [ ! -d "try-devnet" ]; then
    echo "🔍 Cloning try-devnet repository..."
    git clone --recurse-submodules https://github.com/SeismicSystems/try-devnet.git
fi

# Navigate to contract folder
cd try-devnet/packages/contract/ || { echo "❌ Failed to enter contract directory."; exit 1; }

# Deploy the first contract
echo "🚀 Deploying first contract..."
bash script/deploy.sh
if [ $? -ne 0 ]; then
    echo "❌ First contract deployment failed."
    exit 1
fi

# Prompt user to request faucet tokens for the first contract
echo "⚠️ Visit the faucet and enter the address shown in the script."
echo "➡️ Faucet: https://faucet-2.seismicdev.net/"
read -p "Press Enter after funding the wallet..."

# Install bun if not installed
if ! command -v bun &> /dev/null; then
    echo "🔍 Installing bun..."
    curl -fsSL https://bun.sh/install | bash
    source "$HOME/.bashrc"
else
    echo "✅ Bun is already installed."
fi

# Navigate to CLI package
cd ~/try-devnet/packages/cli/ || { echo "❌ Failed to enter CLI directory."; exit 1; }

# Install dependencies with bun
echo "🔍 Installing dependencies with bun..."
bun install

# Deploy the second contract (via transact.sh)
echo "🚀 Deploying second contract..."
bash script/transact.sh
if [ $? -ne 0 ]; then
    echo "❌ Second contract deployment failed."
    exit 1
fi

# Prompt user to request faucet tokens for the second contract
echo "⚠️ Visit the faucet and enter the address shown in the script."
echo "➡️ Faucet: https://faucet-2.seismicdev.net/"
read -p "Press Enter after funding the wallet..."

echo "✅ Seismic Devnet deployment and interaction complete!"

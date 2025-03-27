#!/bin/bash

set -e  # Exit immediately if a command fails
set -o pipefail  # Catch errors in pipes

# Ensure script runs as root (Linux only)
if [[ "$(uname)" == "Linux" && $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root on Linux."
    exit 1
fi

# Detect OS
OS=""
if [[ "$(uname)" == "Darwin" ]]; then
    OS="macOS"
    PACKAGE_MANAGER="brew"
elif [[ "$(uname)" == "Linux" ]]; then
    OS="Linux"
    PACKAGE_MANAGER="apt-get"
else
    echo "❌ Unsupported OS: $(uname)"
    exit 1
fi

echo "✅ Detected OS: $OS"
echo "🔍 Installing required dependencies..."

# Install required dependencies if missing
REQUIRED_TOOLS=("curl" "wget" "git" "jq" "unzip" "bc")

for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v $tool &>/dev/null; then
        echo "🔹 Installing $tool..."
        if [[ "$OS" == "macOS" ]]; then
            brew install $tool
        else
            apt-get install -y $tool
        fi
    else
        echo "✅ $tool is already installed."
    fi
done

# Install Rust if missing
if ! command -v rustc &>/dev/null; then
    echo "🔹 Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env
else
    echo "✅ Rust is already installed."
fi

# Install Seismic Foundry tools if missing
FOUNDATION_DIR="$HOME/.seismic"
BIN_DIR="$FOUNDATION_DIR/bin"
PATH_UPDATE="export PATH=$BIN_DIR:\$PATH"

if ! command -v sfoundryup &>/dev/null; then
    echo "🔍 Installing Seismic Foundry..."
    curl -sL https://raw.githubusercontent.com/SeismicSystems/sfoundryup/main/install.sh | bash
    source ~/.bashrc || source ~/.zshrc
else
    echo "✅ Seismic Foundry is already installed."
fi

# Ensure Seismic tools are installed
echo "🔍 Installing Seismic Foundry tools..."
if ! sfoundryup &>/dev/null; then
    echo "⚠️ First attempt failed. Trying alternative installation method..."
    git clone --branch seismic https://github.com/SeismicSystems/seismic-foundry.git $FOUNDATION_DIR
    cd $FOUNDATION_DIR
    cargo build --release
    mv target/release/* $BIN_DIR/ || true
    echo "$PATH_UPDATE" >> ~/.bashrc || echo "$PATH_UPDATE" >> ~/.zshrc
    source ~/.bashrc || source ~/.zshrc
else
    echo "✅ Seismic Foundry tools are installed."
fi

# Verify tools
TOOLS=("ssolc" "sforge" "scast" "sanvil" "schisel")
for tool in "${TOOLS[@]}"; do
    if ! command -v $tool &>/dev/null; then
        echo "❌ $tool is missing! Installing..."
        sfoundryup
    fi
done

# Ensure the tools are added to PATH
echo "$PATH_UPDATE" >> ~/.bashrc || echo "$PATH_UPDATE" >> ~/.zshrc
source ~/.bashrc || source ~/.zshrc

# Contract Deployment Process
echo "🔍 Checking faucet balance..."
FAUCET_URL="https://faucet.seismic.network"
WALLET_ADDRESS="your-wallet-address"

BALANCE=$(curl -s "$FAUCET_URL/balance/$WALLET_ADDRESS" | jq -r '.balance' || echo "0")
if [[ -z "$BALANCE" || "$BALANCE" == "0" ]]; then
    echo "🚰 Requesting test ETH from faucet..."
    curl -X POST "$FAUCET_URL/request" -d "{\"address\":\"$WALLET_ADDRESS\"}"
    sleep 30
fi

echo "💰 Current balance: $BALANCE ETH"

echo "🚀 Deploying contract..."
sforge build
DEPLOY_OUTPUT=$(sforge deploy --json)
CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | jq -r '.address')

if [[ -z "$CONTRACT_ADDRESS" ]]; then
    echo "❌ Contract deployment failed."
    exit 1
fi

echo "✅ Contract deployed at: $CONTRACT_ADDRESS"

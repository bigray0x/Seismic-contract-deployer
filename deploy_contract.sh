#!/bin/bash

set -e

echo "✅ Detected OS: $(uname -s)"

# Function to install a package if missing
install_if_missing() {
    if ! command -v "$1" &>/dev/null; then
        echo "🔍 Installing $1..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            sudo apt-get update && sudo apt-get install -y "$2"
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            brew install "$2"
        fi
        echo "✅ $1 installed."
    else
        echo "✅ $1 is already installed."
    fi
}

# Install required dependencies
echo "🔍 Installing required dependencies..."
install_if_missing "curl" "curl"
install_if_missing "wget" "wget"
install_if_missing "git" "git"
install_if_missing "jq" "jq"
install_if_missing "unzip" "unzip"
install_if_missing "bc" "bc"

# Install Rust if missing
if ! command -v rustc &>/dev/null; then
    echo "🔍 Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    echo "✅ Rust installed."
else
    echo "✅ Rust is already installed."
fi

# Set Seismic Foundry install path
SEISMIC_DIR="$HOME/.seismic"
BIN_DIR="$SEISMIC_DIR/bin"
SF_COMMAND="$BIN_DIR/sfoundryup"

# Remove broken or failed Seismic Foundry installs
if [[ -d "$SEISMIC_DIR" && ! -f "$SF_COMMAND" ]]; then
    echo "⚠️ Detected incomplete Seismic Foundry install. Cleaning up..."
    rm -rf "$SEISMIC_DIR"
fi

# Install Seismic Foundry if missing
if ! command -v sfoundryup &>/dev/null; then
    echo "🔍 Installing Seismic Foundry..."
    git clone --depth 1 --branch seismic https://github.com/SeismicSystems/seismic-foundry.git "$SEISMIC_DIR"
    cd "$SEISMIC_DIR" && cargo build --release
    mkdir -p "$BIN_DIR"
    mv target/release/* "$BIN_DIR"
    export PATH="$BIN_DIR:$PATH"
    echo "✅ Seismic Foundry installed."
else
    echo "✅ Seismic Foundry is already installed."
fi

# Ensure Seismic Foundry tools are installed
echo "🔍 Installing Seismic Foundry tools..."
if ! "$SF_COMMAND"; then
    echo "⚠️ First attempt failed. Cleaning up and retrying..."
    rm -rf "$SEISMIC_DIR"
    git clone --depth 1 --branch seismic https://github.com/SeismicSystems/seismic-foundry.git "$SEISMIC_DIR"
    cd "$SEISMIC_DIR" && cargo build --release
    mv target/release/* "$BIN_DIR"
    export PATH="$BIN_DIR:$PATH"
    echo "✅ Seismic Foundry tools installed."
else
    echo "✅ Seismic Foundry tools are already installed."
fi

# Ask for wallet address
while true; do
    echo "🔍 Please enter your wallet address:"
    read -r WALLET_ADDRESS

    # Validate wallet format (Ethereum-style)
    if [[ "$WALLET_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo "✅ Wallet address is valid: $WALLET_ADDRESS"
        break
    else
        echo "❌ Invalid wallet address! Please enter a valid Ethereum address (0x...40 hex chars)."
    fi
done

# Check wallet balance
echo "🔍 Checking balance for wallet: $WALLET_ADDRESS..."
BALANCE_RAW=$(seismic-cli balance "$WALLET_ADDRESS" | jq -r '.balance')

# Validate balance output
if [[ -z "$BALANCE_RAW" || "$BALANCE_RAW" == "null" ]]; then
    echo "❌ Error: Failed to retrieve balance."
    exit 1
fi

# Convert balance to a numeric value
BALANCE=$(echo "$BALANCE_RAW" | awk '{print $1+0}')
echo "💰 Current balance: $BALANCE ETH"

# Ensure balance format is valid
if ! [[ "$BALANCE" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "❌ Error: Invalid balance format. Exiting..."
    exit 1
fi

# Request faucet funds if balance is low
if (( $(echo "$BALANCE < 0.1" | bc -l) )); then
    echo "🚰 Requesting funds from faucet for $WALLET_ADDRESS..."
    for i in {1..3}; do
        seismic-cli request-faucet --wallet "$WALLET_ADDRESS" && break || echo "❌ Faucet request failed. Retrying in 30s..."
        sleep 30
    done
else
    echo "✅ Sufficient balance: $BALANCE ETH"
fi

# Deploy contract
echo "🚀 Deploying contract..."
DEPLOYED_CONTRACT=$(seismic-cli deploy contract.sol --wallet "$WALLET_ADDRESS" | jq -r '.contract_address')

# Validate contract deployment
if [[ -z "$DEPLOYED_CONTRACT" || "$DEPLOYED_CONTRACT" == "null" ]]; then
    echo "❌ Error: Contract deployment failed."
    exit 1
fi

echo "✅ Contract deployed at: $DEPLOYED_CONTRACT"

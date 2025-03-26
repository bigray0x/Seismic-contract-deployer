#!/bin/bash

# Stop script on errors
set -e

# Detect OS
OS=$(uname -s)
if [[ "$OS" == "Darwin" ]]; then
    SHELL_RC="$HOME/.zshrc"
else
    SHELL_RC="$HOME/.bashrc"
fi

# Faucet URL
FAUCET_URL="https://faucet-2.seismicdev.net/api/claim"
RPC_URL="https://node-2.seismicdev.net/rpc"
MAX_FAUCET_RETRIES=3

# Function to install dependencies based on OS
install_dependencies() {
    echo "🔧 Installing system dependencies..."
    if [[ "$OS" == "Darwin" ]]; then
        brew install curl git jq unzip build-essential
    else
        sudo apt update && sudo apt install -y curl git jq unzip build-essential
    fi
}

# Function to install Rust
install_rust() {
    if ! command -v rustc &> /dev/null; then
        echo "🔍 Rust not found. Installing..."
        curl https://sh.rustup.rs -sSf | sh -s -- -y
        source "$HOME/.cargo/env"
    else
        echo "✅ Rust is already installed."
    fi
}

# Function to install Seismic Foundry
install_sfoundry() {
    echo "🔍 Checking Seismic Foundry installation..."
    if ! command -v sfoundryup &> /dev/null; then
        echo "🔍 Seismic Foundry not found. Installing..."
        curl -L -H "Accept: application/vnd.github.v3.raw" \
             "https://api.github.com/repos/SeismicSystems/seismic-foundry/contents/sfoundryup/install?ref=seismic" | bash
    else
        echo "✅ Seismic Foundry is already installed."
    fi

    # Ensure it's in PATH
    export PATH="$HOME/.seismic/bin:$PATH"
    source "$SHELL_RC" 2>/dev/null

    if ! command -v sfoundryup &> /dev/null; then
        echo "❌ sfoundryup still not found in PATH. Exiting."
        exit 1
    fi

    echo "🔍 Installing Seismic Foundry tools..."
    if ! sfoundryup -p . &> /dev/null; then
        echo "⚠️ First attempt failed. Trying alternative installation method..."
        if ! sfoundryup -v latest &> /dev/null; then
            echo "❌ Failed to install Seismic Foundry tools!"
            exit 1
        fi
    fi

    # Fix for 'mv' error
    for tool in sanvil scast sforge ssolc; do
        if [[ -f "$HOME/.seismic/bin/$tool" ]]; then
            echo "✅ $tool is already installed. Skipping move operation."
        else
            echo "🔄 Moving $tool to $HOME/.seismic/bin..."
            mv -f "target/release/$tool" "$HOME/.seismic/bin/$tool" 2>/dev/null || true
        fi
    done

    # Final check
    for tool in sanvil scast sforge ssolc; do
        if ! command -v "$tool" &> /dev/null; then
            echo "❌ $tool is still missing after installation attempt. Exiting."
            exit 1
        fi
    done
}

# Function to validate wallet address
validate_wallet() {
    if [[ $1 =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo "✅ Valid Ethereum-style wallet address"
    else
        echo "❌ Invalid wallet address! Use a correct Ethereum-style address (0x...)."
        exit 1
    fi
}

# Function to check wallet balance
check_balance() {
    BALANCE_HEX=$(curl -s -X POST "$RPC_URL" -H "Content-Type: application/json" --data '{
        "jsonrpc": "2.0",
        "method": "eth_getBalance",
        "params": ["'"$WALLET_ADDRESS"'", "latest"],
        "id": 1
    }' | jq -r '.result')

    if [[ "$BALANCE_HEX" == "null" ]]; then
        echo "❌ Error fetching balance!"
        return 1
    fi

    BALANCE_DEC=$((16#${BALANCE_HEX#0x}))
    BALANCE_ETH=$(bc <<< "scale=5; $BALANCE_DEC / 10^18")

    echo "💰 Current balance: $BALANCE_ETH ETH"

    if (( $(echo "$BALANCE_ETH >= 0.1" | bc -l) )); then
        return 0
    else
        return 1
    fi
}

# Function to request test ETH from faucet
request_faucet() {
    local attempt=1
    while [[ $attempt -le $MAX_FAUCET_RETRIES ]]; do
        echo "🚰 Attempt #$attempt: Requesting test ETH..."
        RESPONSE=$(curl -s -X POST "$FAUCET_URL" -H "Content-Type: application/json" --data '{
            "address": "'"$WALLET_ADDRESS"'"
        }')

        if [[ "$RESPONSE" == *"success"* ]]; then
            echo "✅ Faucet request successful!"
            return 0
        else
            echo "❌ Faucet request failed. Retrying in 30s..."
            sleep 30
            ((attempt++))
        fi
    done

    echo "❌ Faucet request failed after $MAX_FAUCET_RETRIES attempts. Exiting."
    exit 1
}

# Request wallet address
read -p "Enter your Seismic Devnet wallet address: " WALLET_ADDRESS
validate_wallet "$WALLET_ADDRESS"

# Install dependencies
install_dependencies

# Install Rust
install_rust

# Install Seismic Foundry
install_sfoundry

# Check wallet balance
if check_balance; then
    echo "✅ Wallet already has enough balance."
else
    request_faucet

    # Wait for funds
    echo "⏳ Waiting for funds..."
    while ! check_balance; do
        echo "⏳ Checking again in 30s..."
        sleep 30
    done
fi

echo "✅ Funds received! Deploying contract..."

# Clone smart contract repo
echo "📦 Cloning contract repository..."
git clone --recurse-submodules https://github.com/SeismicSystems/try-devnet.git
cd try-devnet/packages/contract/

# Deploy contract
echo "🚀 Deploying smart contract..."
bash script/deploy.sh

# Ensure `scast` is installed
if ! command -v scast &> /dev/null; then
    echo "❌ scast not found! Reinstalling tools..."
    sfoundryup -p
    source "$SHELL_RC"

    if ! command -v scast &> /dev/null; then
        echo "❌ scast is still missing. Exiting."
        exit 1
    fi
fi

# Install Bun for transaction execution
echo "🔍 Checking if Bun is installed..."
if ! command -v bun &> /dev/null; then
    echo "🔧 Installing Bun..."
    curl -fsSL https://bun.sh/install | bash
    source "$SHELL_RC"
else
    echo "✅ Bun is already installed."
fi

# Execute transaction
echo "💰 Executing transaction..."
cd ../cli/
bun install
bash script/transact.sh

echo "🎉 Deployment completed successfully!"

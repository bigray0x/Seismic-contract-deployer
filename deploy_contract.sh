#!/bin/bash

# Stop script on errors
set -e

# Faucet URL
FAUCET_URL="https://faucet-2.seismicdev.net/api/claim"

# RPC Endpoint for balance check
RPC_URL="https://node-2.seismicdev.net/rpc"

# Max faucet retry attempts
MAX_FAUCET_RETRIES=3

# Function to check if a command exists and install if missing
check_and_install() {
    if ! command -v "$1" &> /dev/null; then
        echo "🔍 $1 not found. Installing..."
        sudo apt install -y "$2"
    else
        echo "✅ $1 is already installed."
    fi
}

# Function to install Rust if not installed
install_rust() {
    if ! command -v rustc &> /dev/null; then
        echo "🔍 Rust not found. Installing..."
        curl https://sh.rustup.rs -sSf | sh -s -- -y
        source "$HOME/.cargo/env"
    else
        echo "✅ Rust is already installed."
    fi
}

# Function to install Seismic Foundry if not installed
install_sfoundry() {
    if ! command -v sfoundryup &> /dev/null; then
        echo "🔍 Seismic Foundry not found. Installing..."
        curl -L -H "Accept: application/vnd.github.v3.raw" \
             "https://api.github.com/repos/SeismicSystems/seismic-foundry/contents/sfoundryup/install?ref=seismic" | bash
        source ~/.bashrc
        sfoundryup
    else
        echo "✅ Seismic Foundry is already installed."
    fi
}

# Function to validate Ethereum-style wallet address
validate_wallet() {
    if [[ $1 =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo "✅ Supported wallet type detected: Ethereum-style address"
        return 0
    else
        echo "❌ Invalid wallet address! Please enter a valid Ethereum-style address (0x...)."
        exit 1
    fi
}

# Function to check wallet balance
check_balance() {
    BALANCE=$(curl -s -X POST "$RPC_URL" -H "Content-Type: application/json" --data '{
        "jsonrpc": "2.0",
        "method": "eth_getBalance",
        "params": ["'"$WALLET_ADDRESS"'", "latest"],
        "id": 1
    }' | jq -r '.result')

    if [[ "$BALANCE" == "null" ]]; then
        echo "❌ Error fetching balance!"
        return 1
    fi

    BALANCE_WEI=$((16#$BALANCE))
    BALANCE_ETH=$(bc <<< "scale=5; $BALANCE_WEI / 10^18")

    echo "💰 Current balance: $BALANCE_ETH ETH"

    if (( $(echo "$BALANCE_ETH >= 0.1" | bc -l) )); then
        return 0  # Balance is sufficient
    else
        return 1  # Balance is insufficient
    fi
}

# Function to request faucet with retry logic
request_faucet() {
    local attempt=1
    while [[ $attempt -le $MAX_FAUCET_RETRIES ]]; do
        echo "🚰 Attempt #$attempt: Requesting test ETH from faucet..."
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

# Request user wallet address
read -p "Enter your Seismic Devnet wallet address: " WALLET_ADDRESS
validate_wallet "$WALLET_ADDRESS"

# Update system and install dependencies
echo "🔧 Updating system and installing required packages..."
sudo apt update && sudo apt upgrade -y
check_and_install curl curl
check_and_install git git
check_and_install build-essential build-essential
check_and_install file file
check_and_install unzip unzip
check_and_install jq jq

# Install Rust
install_rust

# Install Seismic Foundry
install_sfoundry

# Check if wallet already has funds
if check_balance; then
    echo "✅ Wallet already has sufficient balance. Skipping faucet request."
else
    request_faucet

    # Wait until funds arrive
    echo "⏳ Waiting for test ETH to arrive..."
    while ! check_balance; do
        echo "⏳ Funds not received yet. Checking again in 30 seconds..."
        sleep 30
    done
fi

echo "✅ Funds received! Proceeding with deployment."

# Clone the smart contract repository
echo "📦 Cloning contract repository..."
git clone --recurse-submodules https://github.com/SeismicSystems/try-devnet.git
cd try-devnet/packages/contract/

# Deploy the contract
echo "🚀 Deploying the smart contract..."
bash script/deploy.sh

# Install Bun for transaction execution
echo "🔍 Checking if Bun is installed..."
if ! command -v bun &> /dev/null; then
    echo "🔧 Installing Bun..."
    curl -fsSL https://bun.sh/install | bash
    source ~/.bashrc
else
    echo "✅ Bun is already installed."
fi

# Execute a transaction with the extended contract
echo "💰 Executing transaction with extended contract..."
cd ../cli/
bun install
bash script/transact.sh

echo "🎉 Deployment and interaction completed successfully!"

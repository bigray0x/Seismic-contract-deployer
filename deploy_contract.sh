#!/bin/bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Helper functions
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Ensure required tools are installed
check_and_install_tool() {
    local tool=$1
    local install_cmd=$2
    if ! command -v "$tool" &>/dev/null; then
        info "$tool not found. Installing..."
        eval "$install_cmd"
        if ! command -v "$tool" &>/dev/null; then
            error "Failed to install $tool. Please install it manually and re-run the script."
        fi
        success "$tool installed successfully."
    fi
}

info "Checking required tools..."

check_and_install_tool "foundryup" "curl -L https://foundry.paradigm.xyz | bash"
check_and_install_tool "sforge" "foundryup"
check_and_install_tool "jq" "brew install jq || sudo apt install jq -y"

export PATH="$HOME/.foundry/bin:$PATH"

info "All required tools are installed."

# Check and fund wallet balance if needed
WALLET_ADDRESS=""
while [[ -z "$WALLET_ADDRESS" ]]; do
    read -r -p "🔍 Enter your wallet address: " WALLET_ADDRESS
    [[ -z "$WALLET_ADDRESS" ]] && error "Wallet address cannot be empty!"
done

BALANCE=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_getBalance","params":["'"$WALLET_ADDRESS"'", "latest"],"id":1}' https://node-2.seismicdev.net/rpc | jq -r '.result')

if [[ "$BALANCE" == "0x0" || -z "$BALANCE" ]]; then
    info "Wallet balance is zero. Requesting funds from faucet..."
    curl -X POST -H "Content-Type: application/json" --data '{"address": "'"$WALLET_ADDRESS"'"}' https://faucet-2.seismicdev.net/request
    success "Faucet request sent. Please wait for the funds to arrive."
    sleep 10
fi

# Deploy EncryptedStorage contract
info "Deploying EncryptedStorage to Seismic Devnet..."
while true; do
    read -r -s -p "🔍 Enter your private key (input hidden): " PRIVATE_KEY
    echo
    if [[ "$PRIVATE_KEY" =~ ^[0-9a-fA-F]{64}$ ]]; then
        success "Private key format is valid"
        break
    elif [ -z "$PRIVATE_KEY" ]; then
        echo "❌ Private key cannot be empty!"
    else
        echo "❌ Invalid private key! Must be 64 hex characters."
    fi
done

read -r -p "🔍 Enter an encryption key for EncryptedStorage (uint256, e.g., 12345): " ENCRYPTION_KEY
if [[ "$ENCRYPTION_KEY" =~ ^[0-9]+$ ]]; then
    success "Encryption key set: $ENCRYPTION_KEY"
else
    error "Invalid encryption key! Must be a positive integer."
fi

ENC_DEPLOY_OUTPUT=$(sforge create --rpc-url https://node-2.seismicdev.net/rpc --private-key "$PRIVATE_KEY" --broadcast contract.sol:EncryptedStorage --constructor-args "$ENCRYPTION_KEY" --json 2>&1)

echo "DEBUG: ENC_DEPLOY_OUTPUT=$ENC_DEPLOY_OUTPUT"

# Extract JSON part only
ENC_DEPLOY_JSON=$(echo "$ENC_DEPLOY_OUTPUT" | grep -oP '\{.*\}' || echo "")

if [[ -n "$ENC_DEPLOY_JSON" ]]; then
    ENC_ADDRESS=$(echo "$ENC_DEPLOY_JSON" | jq -r '.deployedTo // ""' 2>/dev/null)
    ENC_TX_HASH=$(echo "$ENC_DEPLOY_JSON" | jq -r '.transactionHash // ""' 2>/dev/null)
else
    ENC_ADDRESS=$(echo "$ENC_DEPLOY_OUTPUT" | grep -oP '(?<=Deployed to: )\S+')
    ENC_TX_HASH=$(echo "$ENC_DEPLOY_OUTPUT" | grep -oP '(?<=Transaction hash: )\S+')
fi

if [[ -n "$ENC_ADDRESS" ]]; then
    success "EncryptedStorage deployed at: $ENC_ADDRESS"
    echo "View on explorer: https://explorer-2.seismicdev.net/address/$ENC_ADDRESS"
    [[ -n "$ENC_TX_HASH" ]] && echo "Transaction hash: $ENC_TX_HASH" && echo "View transaction: https://explorer-2.seismicdev.net/tx/$ENC_TX_HASH"
else
    error "Deployment failed: Could not parse contract address or transaction hash from output"
fi

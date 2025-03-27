#!/bin/bash

# Stop script on errors
set -e

# Detect OS (macOS or Linux)
OS=$(uname -s)
if [[ "$OS" == "Darwin" ]]; then
    SHELL_RC="$HOME/.zshrc"
    # On macOS, use greadlink if available; install via coreutils: brew install coreutils
    READLINK="greadlink"
else
    SHELL_RC="$HOME/.bashrc"
    READLINK="readlink"
fi

# Faucet and RPC settings
FAUCET_URL="https://faucet-2.seismicdev.net/api/claim"
RPC_URL="https://node-2.seismicdev.net/rpc"
MAX_FAUCET_RETRIES=3

########################################
# Function: check_and_install
########################################
check_and_install() {
    if ! command -v "$1" &> /dev/null; then
        echo "🔍 $1 not found. Installing..."
        if [[ "$OS" == "Darwin" ]]; then
            brew install "$2"
        else
            sudo apt install -y "$2"
        fi
    else
        echo "✅ $1 is already installed."
    fi
}

########################################
# Function: install_dependencies
########################################
install_dependencies() {
    echo "🔧 Installing system dependencies..."
    if [[ "$OS" == "Darwin" ]]; then
        brew update && brew upgrade
        check_and_install curl curl
        check_and_install git git
        check_and_install jq jq
        check_and_install unzip unzip
        check_and_install bc bc
    else
        sudo apt update && sudo apt upgrade -y
        check_and_install curl curl
        check_and_install git git
        check_and_install build-essential build-essential
        check_and_install file file
        check_and_install unzip unzip
        check_and_install jq jq
        check_and_install bc bc
    fi
}

########################################
# Function: install_rust
########################################
install_rust() {
    if ! command -v rustc &> /dev/null; then
        echo "🔍 Rust not found. Installing..."
        curl https://sh.rustup.rs -sSf | sh -s -- -y
        source "$HOME/.cargo/env"
    else
        echo "✅ Rust is already installed."
    fi
}

########################################
# Function: install_sfoundry
########################################
install_sfoundry() {
    echo "🔍 Checking Seismic Foundry installation..."
    if ! command -v sfoundryup &> /dev/null; then
        echo "🔍 Seismic Foundry not found. Installing..."
        curl -L -H "Accept: application/vnd.github.v3.raw" \
             "https://api.github.com/repos/SeismicSystems/seismic-foundry/contents/sfoundryup/install?ref=seismic" | bash
        source "$SHELL_RC"
    else
        echo "✅ Seismic Foundry is already installed."
    fi

    # Ensure Seismic Foundry binary directory is in PATH
    export PATH="$HOME/.seismic/bin:$PATH"
    source "$SHELL_RC" 2>/dev/null

    if ! command -v sfoundryup &> /dev/null; then
        echo "❌ sfoundryup still not found in PATH. Exiting."
        exit 1
    fi
}

########################################
# Function: install_seismic_foundry_tools
########################################
install_seismic_foundry_tools() {
    echo "🔍 Installing Seismic Foundry tools..."
    # Run sfoundryup with no options (as per instructions)
    set +e
    OUTPUT=$(sfoundryup 2>&1)
    RETCODE=$?
    set -e
    if [ $RETCODE -ne 0 ]; then
        # Check if all essential tools are present
        MISSING=false
        for tool in sanvil scast sforge ssolc; do
            if ! command -v "$tool" &> /dev/null; then
                echo "❌ $tool is missing."
                MISSING=true
            fi
        done
        if [ "$MISSING" = false ]; then
            echo "✅ Essential tools are present despite sfoundryup error. Proceeding..."
        else
            echo "❌ Failed to install Seismic Foundry tools!"
            echo "$OUTPUT"
            exit 1
        fi
    else
        echo "✅ Seismic Foundry tools installed successfully."
    fi

    # Fix for 'mv' error: Only move file if source and destination differ
    for tool in sanvil scast sforge ssolc; do
        src="target/release/$tool"
        dst="$HOME/.seismic/bin/$tool"
        if [[ -f "$dst" ]]; then
            if [[ "$($READLINK -f "$src")" == "$($READLINK -f "$dst")" ]]; then
                echo "✅ $tool is already installed and up-to-date. Skipping move."
            else
                echo "🔄 Updating $tool at $dst..."
                mv -f "$src" "$dst"
            fi
        else
            echo "🔄 Moving $tool to $dst..."
            mv -f "$src" "$dst" 2>/dev/null || true
        fi
    done

    # Final check for essential tools
    for tool in sanvil scast sforge ssolc; do
        if ! command -v "$tool" &> /dev/null; then
            echo "❌ $tool is still missing after installation attempt. Exiting."
            exit 1
        fi
    done
}

########################################
# Function: validate_wallet
########################################
validate_wallet() {
    if [[ $1 =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo "✅ Supported wallet type detected: Ethereum-style address"
    else
        echo "❌ Invalid wallet address! Please enter a valid Ethereum-style address (0x...)."
        exit 1
    fi
}

########################################
# Function: check_balance
########################################
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
        return 0  # Balance is sufficient
    else
        return 1  # Balance is insufficient
    fi
}

########################################
# Function: request_faucet
########################################
request_faucet() {
    local attempt=1
    while [[ $attempt -le $MAX_FAUCET_RETRIES ]]; do
        echo "🚰 Attempt #$attempt: Requesting test ETH from faucet..."
        RESPONSE=$(curl -s -X POST "$FAUCET_URL" -H "Content-Type: application/json" --data '{
            "address": "'"$WALLET_ADDRESS"'" 
        }')
        echo "🔍 Faucet response: $RESPONSE"
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

########################################
# Main Execution
########################################

# Request user wallet address
read -p "Enter your Seismic Devnet wallet address: " WALLET_ADDRESS
validate_wallet "$WALLET_ADDRESS"

# Install system dependencies
install_dependencies

# Install Rust
install_rust

# Install Seismic Foundry and its tools
install_sfoundry
install_seismic_foundry_tools

# Check if wallet already has funds; if not, request faucet funds.
if check_balance; then
    echo "✅ Wallet already has sufficient balance. Skipping faucet request."
else
    request_faucet
    echo "⏳ Waiting for test ETH to arrive..."
    while ! check_balance; do
        echo "⏳ Funds not received yet. Checking again in 30 seconds..."
        sleep 30
    done
fi

echo "✅ Funds received! Proceeding with deployment."

# Clone smart contract repository
echo "📦 Cloning contract repository..."
git clone --recurse-submodules https://github.com/SeismicSystems/try-devnet.git
cd try-devnet/packages/contract/

# Deploy contract
echo "🚀 Deploying smart contract..."
bash script/deploy.sh

# Ensure essential Seismic tools (e.g., scast) are installed
if ! command -v scast &> /dev/null; then
    echo "❌ scast not found! Trying to reinstall Seismic Foundry tools..."
    sfoundryup || true
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

# Execute transaction with extended contract
echo "💰 Executing transaction with extended contract..."
cd ../cli/
bun install
bash script/transact.sh

echo "🎉 Deployment and interaction completed successfully!"

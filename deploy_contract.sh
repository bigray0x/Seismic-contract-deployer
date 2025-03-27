#!/bin/bash

set -e

# Detect OS
OS=$(uname -s)
echo "✅ Detected OS: $OS"

# Function to install a package if missing
install_if_missing() {
    local cmd="$1" pkg="$2"
    if ! command -v "$cmd" &>/dev/null; then
        echo "🔍 Installing $cmd..."
        case "$OS" in
            Linux)
                if command -v apt-get &>/dev/null; then
                    sudo apt-get update && sudo apt-get install -y "$pkg"
                else
                    echo "❌ Only apt-get-based Linux is supported. Install $pkg manually."
                    exit 1
                fi
                ;;
            Darwin)
                if ! command -v brew &>/dev/null; then
                    echo "❌ Homebrew required on macOS. Install it from https://brew.sh/"
                    exit 1
                fi
                brew install "$pkg"
                ;;
            *)
                echo "❌ Unsupported OS: $OS"
                exit 1
                ;;
        esac
        echo "✅ $cmd installed."
    else
        echo "✅ $cmd is already installed."
    fi
}

# Install dependencies
echo "🔍 Installing required dependencies..."
install_if_missing "curl" "curl"
install_if_missing "git" "git"
install_if_missing "jq" "jq"
install_if_missing "unzip" "unzip"

# Install Rust
if ! command -v rustc &>/dev/null; then
    echo "🔍 Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || {
        echo "❌ Failed to install Rust."
        exit 1
    }
    [ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"
    echo "✅ Rust installed."
else
    echo "✅ Rust is already installed."
fi

# Install bun
if ! command -v bun &>/dev/null; then
    echo "🔍 Installing bun..."
    curl -fsSL https://bun.sh/install | bash || {
        echo "❌ Failed to install bun."
        exit 1
    }
    [ -f "$HOME/.bun/bin/bun" ] && export PATH="$HOME/.bun/bin:$PATH"
    echo "✅ bun installed."
else
    echo "✅ bun is already installed."
fi

# Install sfoundryup and update PATH
SEISMIC_BIN="$HOME/.seismic/bin"
if ! command -v sfoundryup &>/dev/null; then
    echo "🔍 Installing sfoundryup..."
    curl -L -H "Accept: application/vnd.github.v3.raw" \
        "https://api.github.com/repos/SeismicSystems/seismic-foundry/contents/sfoundryup/install?ref=seismic" | bash || {
        echo "❌ Failed to install sfoundryup."
        exit 1
    }
    # Add Seismic bin directory to PATH immediately
    export PATH="$SEISMIC_BIN:$PATH"
    # Source .bashrc if it was updated (redundancy)
    [ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc"
    # Run sfoundryup to install tools
    sfoundryup || {
        echo "❌ Failed to run sfoundryup to install Seismic Foundry tools."
        exit 1
    }
    echo "✅ sfoundryup and Seismic Foundry tools installed."
else
    echo "✅ sfoundryup is already installed."
    export PATH="$SEISMIC_BIN:$PATH"  # Ensure PATH is set for existing install
fi

# Verify seismic-cli and sforge
for cmd in seismic-cli sforge; do
    command -v "$cmd" >/dev/null || {
        echo "❌ $cmd not found. Running sfoundryup again to ensure tools are installed..."
        sfoundryup || {
            echo "❌ Failed to install $cmd with sfoundryup."
            exit 1
        }
    }
done

# Clone try-devnet repository
if [ ! -d "try-devnet" ]; then
    echo "🔍 Cloning try-devnet repository..."
    git clone --recurse-submodules https://github.com/SeismicSystems/try-devnet.git || {
        echo "❌ Failed to clone try-devnet."
        exit 1
    }
fi
cd try-devnet/packages/contract || {
    echo "❌ Failed to navigate to contract directory."
    exit 1
}

# Create contract.sol if missing
if [ ! -f "contract.sol" ]; then
    echo "⚠️ contract.sol not found. Creating a default encrypted contract..."
    cat << 'EOF' > contract.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract EncryptedCounter {
    uint256 private counter;

    function increment() public {
        counter += 1;
    }

    function getCounter() public view returns (uint256) {
        return counter;
    }
}
EOF
    echo "✅ Created contract.sol"
else
    echo "✅ contract.sol found."
fi

# Validate contract syntax
echo "🔍 Validating contract syntax..."
sforge compile contract.sol || {
    echo "❌ Contract compilation failed. Please fix syntax errors."
    exit 1
}

# Get and validate wallet address
while true; do
    read -r -p "🔍 Please enter your wallet address: " WALLET_ADDRESS
    if [[ "$WALLET_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo "✅ Wallet address is valid: $WALLET_ADDRESS"
        break
    else
        echo "❌ Invalid wallet address! Must be 0x followed by 40 hex chars."
    fi
done

# Check wallet balance
echo "🔍 Checking balance for wallet: $WALLET_ADDRESS..."
BALANCE_JSON=$(seismic-cli balance "$WALLET_ADDRESS") || {
    echo "❌ Failed to retrieve balance."
    exit 1
}
BALANCE=$(echo "$BALANCE_JSON" | jq -r '.balance // "0"')
if ! [[ "$BALANCE" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "❌ Invalid balance format: $BALANCE"
    exit 1
fi
BALANCE=$(echo "$BALANCE" | bc 2>/dev/null)
echo "💰 Current balance: $BALANCE ETH"

# Request faucet funds if balance is low
if (( $(echo "$BALANCE < 0.1" | bc -l) )); then
    echo "🚰 Requesting funds from faucet for $WALLET_ADDRESS..."
    echo "Please visit https://faucet-2.seismicdev.net/, enter $WALLET_ADDRESS, and request tokens."
    read -p "Press Enter after requesting funds (wait 15-30 seconds)..."
    # Verify balance increased (optional check)
    BALANCE_JSON=$(seismic-cli balance "$WALLET_ADDRESS") || {
        echo "❌ Failed to retrieve updated balance."
        exit 1
    }
    BALANCE=$(echo "$BALANCE_JSON" | jq -r '.balance // "0"')
    BALANCE=$(echo "$BALANCE" | bc 2>/dev/null)
    echo "💰 Updated balance: $BALANCE ETH"
fi

# Deploy contract
echo "🚀 Deploying contract..."
DEPLOY_OUTPUT=$(seismic-cli deploy contract.sol --wallet "$WALLET_ADDRESS") || {
    echo "❌ Failed to deploy contract."
    exit 1
}
DEPLOYED_CONTRACT=$(echo "$DEPLOY_OUTPUT" | jq -r '.contract_address // ""')
if [ -z "$DEPLOYED_CONTRACT" ]; then
    TX_HASH=$(echo "$DEPLOY_OUTPUT" | jq -r '.transaction_hash // ""')
    if [ -n "$TX_HASH" ]; then
        echo "⏳ Transaction sent ($TX_HASH), awaiting confirmation..."
        exit 0
    else
        echo "❌ Deployment failed: No address or transaction hash returned."
        exit 1
    fi
fi
echo "✅ Contract deployed at: $DEPLOYED_CONTRACT"

# Optional: Interact with the contract
echo "🔍 Setting up CLI for interaction..."
cd ../cli || {
    echo "❌ Failed to navigate to cli directory."
    exit 1
}
bun install || {
    echo "❌ Failed to install CLI dependencies."
    exit 1
}
echo "🔍 Running transact.sh to interact with contract..."
bash script/transact.sh || {
    echo "❌ Failed to interact with contract."
    exit 1
}

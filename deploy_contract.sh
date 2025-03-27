#!/bin/bash

set -euo pipefail

# Detect OS
OS=$(uname -s)
echo "✅ Detected OS: $OS"

# Colors for output
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' GREEN='' BOLD='' RESET=''
fi

error() { echo -e "${RED}❌ Error:${RESET} $*" >&2; exit 1; }
info() { echo -e "${GREEN}🔍${RESET} $*"; }
success() { echo -e "${GREEN}✅${RESET} $*"; }

# Install a package if missing
install_if_missing() {
    local cmd="$1" pkg="$2"
    if ! command -v "$cmd" &>/dev/null; then
        info "Installing $cmd..."
        case "$OS" in
            Linux) sudo apt-get update && sudo apt-get install -y "$pkg" || error "Failed to install $pkg" ;;
            Darwin) brew install "$pkg" || error "Failed to install $pkg (ensure Homebrew is installed)" ;;
            *) error "Unsupported OS: $OS" ;;
        esac
        success "$cmd installed."
    else
        success "$cmd is already installed."
    fi
}

# Install dependencies
info "Installing required dependencies..."
install_if_missing "curl" "curl"
install_if_missing "git" "git"
install_if_missing "jq" "jq"
install_if_missing "unzip" "unzip"
install_if_missing "bc" "bc"

# Install Rust
if ! command -v rustc &>/dev/null; then
    info "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || error "Failed to install Rust"
    [ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"
    success "Rust installed."
else
    success "Rust is already installed."
fi

# Install Bun
if ! command -v bun &>/dev/null; then
    info "Installing Bun..."
    curl -fsSL https://bun.sh/install | bash || error "Failed to install Bun"
    export PATH="$HOME/.bun/bin:$PATH"
    command -v bun &>/dev/null || error "bun command not found after installation"
    success "Bun installed."
else
    success "Bun is already installed."
fi

# Install Seismic Foundry tools
SEISMIC_DIR="$HOME/.seismic"
BIN_DIR="$SEISMIC_DIR/bin"
SFORGE="$BIN_DIR/sforge"
SANVIL="$BIN_DIR/sanvil"
SSOLC="/usr/local/bin/ssolc"
SOURCE_DIR="$SEISMIC_DIR/source"

if [ ! -f "$SFORGE" ] || [ ! -f "$SANVIL" ]; then
    info "Installing Seismic Foundry from source..."
    mkdir -p "$SOURCE_DIR" || error "Failed to create source directory"
    cd "$SOURCE_DIR" || error "Failed to navigate to source dir"
    if [ ! -d ".git" ]; then
        git clone --branch seismic https://github.com/SeismicSystems/seismic-foundry.git . || error "Failed to clone seismic-foundry"
    fi
    cargo install --root="$SEISMIC_DIR" --profile dev --path ./crates/forge --locked || error "Failed to install sforge"
    cargo install --root="$SEISMIC_DIR" --profile dev --path ./crates/anvil --locked || error "Failed to install sanvil"
    export PATH="$BIN_DIR:$PATH"
    command -v sforge &>/dev/null || error "sforge command not found after installation"
    success "sforge and sanvil installed and verified."
else
    success "sforge and sanvil are already installed."
    command -v sforge &>/dev/null || error "sforge command not found despite binary existing"
fi

# Install ssolc
if ! command -v ssolc &>/dev/null; then
    info "Installing ssolc..."
    case "$OS" in
        Linux) curl -L "https://github.com/SeismicSystems/seismic-foundry/releases/latest/download/ssolc-linux-x86_64.tar.gz" -o ssolc.tar.gz || error "Failed to download ssolc" ;;
        Darwin) curl -L "https://github.com/SeismicSystems/seismic-foundry/releases/latest/download/ssolc-darwin-x86_64.tar.gz" -o ssolc.tar.gz || error "Failed to download ssolc" ;;
        *) error "Unsupported OS for ssolc installation" ;;
    esac
    sudo tar -xzf ssolc.tar.gz -C /usr/local/bin || error "Failed to extract ssolc"
    rm ssolc.tar.gz
    sudo chmod +x "$SSOLC" || error "Failed to set ssolc permissions"
    success "ssolc installed at $SSOLC"
else
    success "ssolc is already installed."
fi

# Ensure PATH includes all tools
export PATH="$HOME/.bun/bin:$BIN_DIR:/usr/local/bin:$PATH"

# Return to home directory
cd "$HOME" || error "Failed to return to home directory"

# Create contract.sol
if [ ! -f "contract.sol" ]; then
    info "Creating contract file..."
    cat << 'EOF' > contract.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract EncryptedStorage {
    uint256 private storedValue;
    uint256 private encryptionKey;

    constructor(uint256 _encryptionKey) {
        encryptionKey = _encryptionKey;
    }

    function setValue(uint256 _value) public {
        storedValue = _value ^ encryptionKey;
    }

    function getValue() public view returns (uint256) {
        return storedValue ^ encryptionKey;
    }
}
EOF
    success "contract.sol created."
else
    success "contract.sol already exists."
fi

# Compile contract
info "Compiling contract..."
sforge compile contract.sol || error "Contract compilation failed"

# Request wallet address
while true; do
    read -r -p "Enter your wallet address: " WALLET_ADDRESS
    [[ "$WALLET_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]] && break
    error "Invalid wallet address."
done
success "Wallet address: $WALLET_ADDRESS"

# Check and fund balance
BALANCE_JSON=$(sforge script --rpc-url https://node-2.seismicdev.net/rpc --json check_balance.sol --sig "getBalance(address)(uint256)" "$WALLET_ADDRESS")
BALANCE=$(echo "$BALANCE_JSON" | jq -r '.returns."0".value // "0"')
BALANCE=$(echo "$BALANCE" | awk '{print $1 / 10^18}')
success "Balance: $BALANCE ETH"

if (( $(echo "$BALANCE < 0.1" | bc -l) )); then
    info "Requesting funds from faucet..."
    echo "Visit: https://faucet-2.seismicdev.net"
    read -r -p "Press Enter after requesting..."
fi

# Deploy contract
read -r -s -p "Enter your private key: " PRIVATE_KEY
echo
read -r -p "Enter encryption key (uint256): " ENCRYPTION_KEY
ENC_DEPLOY_OUTPUT=$(sforge create --rpc-url https://node-2.seismicdev.net/rpc --private-key "$PRIVATE_KEY" --broadcast contract.sol:EncryptedStorage --constructor-args "$ENCRYPTION_KEY" --json)
ENC_ADDRESS=$(echo "$ENC_DEPLOY_OUTPUT" | jq -r '.deployedTo // ""')
success "Contract deployed at: $ENC_ADDRESS"
echo "Explorer: https://explorer-2.seismicdev.net/address/$ENC_ADDRESS"

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
    if ! command -v sforge &>/dev/null; then
        error "sforge command not found after installation"
    fi
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
    command -v ssolc &>/dev/null || error "ssolc command not found after installation"
else
    success "ssolc is already installed."
    command -v ssolc &>/dev/null || error "ssolc command not found despite binary existing"
fi

# Return to home directory
cd "$HOME" || error "Failed to return to home directory"

# Create EncryptedStorage contract if missing
if [ ! -f "encrypted_storage.sol" ]; then
    info "Creating default encrypted contract (EncryptedStorage)..."
    cat << 'EOF' > encrypted_storage.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract EncryptedStorage {
    uint256 private encryptedValue;
    uint256 private encryptionKey;

    constructor(uint256 _key) {
        encryptionKey = _key;
    }

    function setEncryptedValue(uint256 _value) public {
        encryptedValue = _value ^ encryptionKey;
    }

    function getDecryptedValue() public view returns (uint256) {
        return encryptedValue ^ encryptionKey;
    }

    function getEncryptedValue() public view returns (uint256) {
        return encryptedValue;
    }
}
EOF
    success "encrypted_storage.sol created."
else
    success "encrypted_storage.sol already exists."
fi

# Create SimpleStorage contract if missing
if [ ! -f "simple_storage.sol" ]; then
    info "Creating default standard contract (SimpleStorage)..."
    cat << 'EOF' > simple_storage.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SimpleStorage {
    uint256 private storedValue;

    function setValue(uint256 _value) public {
        storedValue = _value;
    }

    function getValue() public view returns (uint256) {
        return storedValue;
    }
}
EOF
    success "simple_storage.sol created."
else
    success "simple_storage.sol already exists."
fi

# Validate contract syntax
info "Validating EncryptedStorage contract syntax..."
sforge compile encrypted_storage.sol || error "EncryptedStorage compilation failed. Fix syntax errors."
info "Validating SimpleStorage contract syntax..."
sforge compile simple_storage.sol || error "SimpleStorage compilation failed. Fix syntax errors."

# Get and validate wallet address
while true; do
    read -r -p "🔍 Please enter your wallet address: " WALLET_ADDRESS
    if [[ "$WALLET_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        success "Wallet address is valid: $WALLET_ADDRESS"
        break
    else
        echo "❌ Invalid wallet address! Must be 0x followed by 40 hex chars."
    fi
done

# Check balance
info "Checking balance for wallet: $WALLET_ADDRESS..."
cat << EOF > check_balance.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract BalanceChecker {
    function getBalance(address account) public view returns (uint256) {
        return account.balance;
    }
}
EOF
BALANCE_JSON=$(sforge script --rpc-url https://node-2.seismicdev.net/rpc --json check_balance.sol --sig "getBalance(address)(uint256)" "$WALLET_ADDRESS") || {
    rm check_balance.sol
    error "Failed to retrieve balance with sforge script"
}
echo "DEBUG: BALANCE_JSON=$BALANCE_JSON"
rm check_balance.sol
BALANCE_HEX=$(echo "$BALANCE_JSON" | jq -r '.returns."0".value // "0"')
if [[ "$BALANCE_HEX" =~ ^[0-9]+$ ]]; then
    BALANCE=$(echo "$BALANCE_HEX" | awk '{print $1 / 10^18}')
else
    BALANCE="0"
fi
[[ "$BALANCE" =~ ^[0-9]+(\.[0-9]+)?$ ]] || error "Invalid balance format: $BALANCE"
success "Current balance: $BALANCE ETH"

# Request faucet funds if balance is low (0.2 ETH for two deployments)
if (( $(echo "$BALANCE < 0.2" | bc -l) )); then
    info "Requesting funds from faucet for $WALLET_ADDRESS..."
    echo "Visit https://faucet-2.seismicdev.net, enter $WALLET_ADDRESS, and request tokens."
    read -r -p "Press Enter after requesting funds (wait 15-30s for processing)..."
    # Recheck balance
    cat << EOF > check_balance.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract BalanceChecker {
    function getBalance(address account) public view returns (uint256) {
        return account.balance;
    }
}
EOF
    BALANCE_JSON=$(sforge script --rpc-url https://node-2.seismicdev.net/rpc --json check_balance.sol --sig "getBalance(address)(uint256)" "$WALLET_ADDRESS") || {
        rm check_balance.sol
        error "Failed to retrieve balance with sforge script"
    }
    echo "DEBUG: BALANCE_JSON=$BALANCE_JSON"
    rm check_balance.sol
    BALANCE_HEX=$(echo "$BALANCE_JSON" | jq -r '.returns."0".value // "0"')
    if [[ "$BALANCE_HEX" =~ ^[0-9]+$ ]]; then
        BALANCE=$(echo "$BALANCE_HEX" | awk '{print $1 / 10^18}')
    else
        BALANCE="0"
    fi
    success "Updated balance: $BALANCE ETH"
fi

# Get private key and encryption key
info "Deploying contracts to Seismic Devnet..."
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
if ! [[ "$ENCRYPTION_KEY" =~ ^[0-9]+$ ]]; then
    error "Encryption key must be a positive integer!"
fi
success "Encryption key set: $ENCRYPTION_KEY"

# Deploy EncryptedStorage
info "Deploying EncryptedStorage contract..."
ENC_DEPLOY_OUTPUT=$(sforge create --rpc-url https://node-2.seismicdev.net/rpc --private-key "$PRIVATE_KEY" --broadcast encrypted_storage.sol:EncryptedStorage --constructor-args "$ENCRYPTION_KEY" --json) || {
    echo "DEBUG: ENC_DEPLOY_OUTPUT=$ENC_DEPLOY_OUTPUT"
    error "Failed to deploy EncryptedStorage contract"
}
echo "DEBUG: ENC_DEPLOY_OUTPUT=$ENC_DEPLOY_OUTPUT"
ENC_DEPLOYED_CONTRACT=$(echo "$ENC_DEPLOY_OUTPUT" | jq -r '.deployedTo // ""')
if [ -z "$ENC_DEPLOYED_CONTRACT" ]; then
    ENC_TX_HASH=$(echo "$ENC_DEPLOY_OUTPUT" | jq -r '.transactionHash // ""')
    [ -n "$ENC_TX_HASH" ] && success "EncryptedStorage transaction sent ($ENC_TX_HASH), view at https://explorer-2.seismicdev.net/tx/$ENC_TX_HASH" || error "EncryptedStorage deployment failed: No address or transaction hash returned"
else
    success "EncryptedStorage deployed at: $ENC_DEPLOYED_CONTRACT"
    echo "View on explorer: https://explorer-2.seismicdev.net/address/$ENC_DEPLOYED_CONTRACT"
fi

# Deploy SimpleStorage
info "Deploying SimpleStorage contract..."
STD_DEPLOY_OUTPUT=$(sforge create --rpc-url https://node-2.seismicdev.net/rpc --private-key "$PRIVATE_KEY" --broadcast simple_storage.sol:SimpleStorage --json) || {
    echo "DEBUG: STD_DEPLOY_OUTPUT=$STD_DEPLOY_OUTPUT"
    error "Failed to deploy SimpleStorage contract"
}
echo "DEBUG: STD_DEPLOY_OUTPUT=$STD_DEPLOY_OUTPUT"
STD_DEPLOYED_CONTRACT=$(echo "$STD_DEPLOY_OUTPUT" | jq -r '.deployedTo // ""')
if [ -z "$STD_DEPLOYED_CONTRACT" ]; then
    STD_TX_HASH=$(echo "$STD_DEPLOY_OUTPUT" | jq -r '.transactionHash // ""')
    [ -n "$STD_TX_HASH" ] && success "SimpleStorage transaction sent ($STD_TX_HASH), view at https://explorer-2.seismicdev.net/tx/$STD_TX_HASH" || error "SimpleStorage deployment failed: No address or transaction hash returned"
else
    success "SimpleStorage deployed at: $STD_DEPLOYED_CONTRACT"
    echo "View on explorer: https://explorer-2.seismicdev.net/address/$STD_DEPLOYED_CONTRACT"
fi

# Interact with EncryptedStorage
info "Interacting with EncryptedStorage contract..."
SET_ENC_VALUE="42"
SET_ENC_OUTPUT=$(sforge cast send --rpc-url https://node-2.seismicdev.net/rpc --private-key "$PRIVATE_KEY" "$ENC_DEPLOYED_CONTRACT" "setEncryptedValue(uint256)" "$SET_ENC_VALUE" --json) || {
    echo "DEBUG: SET_ENC_OUTPUT=$SET_ENC_OUTPUT"
    error "Failed to set encrypted value"
}
SET_ENC_TX_HASH=$(echo "$SET_ENC_OUTPUT" | jq -r '.transactionHash // ""')
[ -n "$SET_ENC_TX_HASH" ] && success "Set encrypted value $SET_ENC_VALUE, tx: $SET_ENC_TX_HASH" || error "Failed to extract set transaction hash"
echo "View set transaction: https://explorer-2.seismicdev.net/tx/$SET_ENC_TX_HASH"

ENC_VALUE=$(sforge cast call --rpc-url https://node-2.seismicdev.net/rpc "$ENC_DEPLOYED_CONTRACT" "getEncryptedValue()(uint256)") || error "Failed to get encrypted value"
success "Encrypted value on-chain: $(echo "$ENC_VALUE" | tr -d '"')"
DEC_VALUE=$(sforge cast call --rpc-url https://node-2.seismicdev.net/rpc "$ENC_DEPLOYED_CONTRACT" "getDecryptedValue()(uint256)") || error "Failed to get decrypted value"
success "Decrypted value: $(echo "$DEC_VALUE" | tr -d '"')"
[ "$(echo "$DEC_VALUE" | tr -d '"')" -eq "$SET_ENC_VALUE" ] && success "Encrypted value verified!" || echo "⚠️ Warning: Decrypted value does not match set value"

# Interact with SimpleStorage
info "Interacting with SimpleStorage contract..."
SET_STD_VALUE="100"
SET_STD_OUTPUT=$(sforge cast send --rpc-url https://node-2.seismicdev.net/rpc --private-key "$PRIVATE_KEY" "$STD_DEPLOYED_CONTRACT" "setValue(uint256)" "$SET_STD_VALUE" --json) || {
    echo "DEBUG: SET_STD_OUTPUT=$SET_STD_OUTPUT"
    error "Failed to set standard value"
}
SET_STD_TX_HASH=$(echo "$SET_STD_OUTPUT" | jq -r '.transactionHash // ""')
[ -n "$SET_STD_TX_HASH" ] && success "Set standard value $SET_STD_VALUE, tx: $SET_STD_TX_HASH" || error "Failed to extract set transaction hash"
echo "View set transaction: https://explorer-2.seismicdev.net/tx/$SET_STD_TX_HASH"

STD_VALUE=$(sforge cast call --rpc-url https://node-2.seismicdev.net/rpc "$STD_DEPLOYED_CONTRACT" "getValue()(uint256)") || error "Failed to get standard value"
success "Retrieved standard value: $(echo "$STD_VALUE" | tr -d '"')"
[ "$(echo "$STD_VALUE" | tr -d '"')" -eq "$SET_STD_VALUE" ] && success "Standard value verified!" || echo "⚠️ Warning: Retrieved value does not match set value"

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

# Reload shell profile
reload_shell_profile() {
    local shell_profile
    case "$(basename "$SHELL")" in
        bash) shell_profile="$HOME/.bashrc" ;;
        zsh) shell_profile="$HOME/.zshrc" ;;
        *) shell_profile="$HOME/.profile" ;;
    esac
    if [ -f "$shell_profile" ]; then
        source "$shell_profile" && success "Shell profile reloaded from $shell_profile"
    else
        info "No shell profile found at $shell_profile, relying on current session PATH"
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
    [ -f "$HOME/.bun/bin/bun" ] && export PATH="$HOME/.bun/bin:$PATH"
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
    echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$HOME/.bashrc"
    export PATH="$BIN_DIR:$PATH"
    reload_shell_profile
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

# Placeholder for seismic-cli installation and check (uncomment and adjust if installation method is known)
# SEISMIC_CLI="$BIN_DIR/seismic-cli"
# if ! command -v seismic-cli &>/dev/null; then
#     info "Installing seismic-cli..."
#     # Example: Hypothetical installation (replace with actual method)
#     # curl -L "https://some-source/seismic-cli.tar.gz" -o seismic-cli.tar.gz || error "Failed to download seismic-cli"
#     # tar -xzf seismic-cli.tar.gz -C "$BIN_DIR" || error "Failed to extract seismic-cli"
#     # rm seismic-cli.tar.gz
#     # chmod +x "$SEISMIC_CLI" || error "Failed to set seismic-cli permissions"
#     echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$HOME/.bashrc"
#     export PATH="$BIN_DIR:$PATH"
#     reload_shell_profile
#     if ! command -v seismic-cli &>/dev/null; then
#         error "seismic-cli command not found after installation"
#     fi
#     success "seismic-cli installed and verified."
# else
#     success "seismic-cli is already installed."
#     command -v seismic-cli &>/dev/null || error "seismic-cli command not found despite binary existing"
# fi

# Return to home directory
cd "$HOME" || error "Failed to return to home directory"

# Create contract.sol if missing
if [ ! -f "contract.sol" ]; then
    info "Creating default encrypted contract (SimpleStorage)..."
    cat << 'EOF' > contract.sol
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
    success "contract.sol created."
else
    success "contract.sol already exists."
fi

# Validate contract syntax
info "Validating contract syntax..."
sforge compile contract.sol || error "Contract compilation failed. Fix syntax errors in contract.sol"

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

# Create a temporary script to check balance
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
rm check_balance.sol
BALANCE_HEX=$(echo "$BALANCE_JSON" | jq -r '(.returns.getBalance.value // .returns[0].value // .balance // "0")' | tr '[:upper:]' '[:lower:]')
if [[ "$BALANCE_HEX" =~ ^0x[0-9a-f]+$ ]]; then
    BALANCE=$(printf "%d" "$BALANCE_HEX" | awk '{print $1 / 10^18}')  # Convert hex wei to ETH
elif [[ "$BALANCE_HEX" =~ ^[0-9]+$ ]]; then
    BALANCE=$(echo "$BALANCE_HEX" | awk '{print $1 / 10^18}')  # Assume decimal wei
else
    BALANCE="0"
fi
[[ "$BALANCE" =~ ^[0-9]+(\.[0-9]+)?$ ]] || error "Invalid balance format: $BALANCE"
success "Current balance: $BALANCE ETH"

# Request faucet funds if balance is low
if (( $(echo "$BALANCE < 0.1" | bc -l) )); then
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
    rm check_balance.sol
    BALANCE_HEX=$(echo "$BALANCE_JSON" | jq -r '(.returns.getBalance.value // .returns[0].value // .balance // "0")' | tr '[:upper:]' '[:lower:]')
    if [[ "$BALANCE_HEX" =~ ^0x[0-9a-f]+$ ]]; then
        BALANCE=$(printf "%d" "$BALANCE_HEX" | awk '{print $1 / 10^18}')
    elif [[ "$BALANCE_HEX" =~ ^[0-9]+$ ]]; then
        BALANCE=$(echo "$BALANCE_HEX" | awk '{print $1 / 10^18}')
    else
        BALANCE="0"
    fi
    success "Updated balance: $BALANCE ETH"
fi

# Deploy contract using sforge
info "Deploying contract to Seismic Devnet..."
read -r -s -p "🔍 Enter your private key (input hidden): " PRIVATE_KEY
echo
DEPLOY_OUTPUT=$(sforge create --rpc-url https://node-2.seismicdev.net/rpc --private-key "$PRIVATE_KEY" contract.sol:SimpleStorage --json) || error "Failed to deploy contract"
DEPLOYED_CONTRACT=$(echo "$DEPLOY_OUTPUT" | jq -r '.deployedTo // ""')
if [ -z "$DEPLOYED_CONTRACT" ]; then
    TX_HASH=$(echo "$DEPLOY_OUTPUT" | jq -r '.transactionHash // ""')
    [ -n "$TX_HASH" ] && success "Transaction sent ($TX_HASH), view at https://explorer-2.seismicdev.net/tx/$TX_HASH" && exit 0
    error "Deployment failed: No address or transaction hash returned"
fi
success "Contract deployed at: $DEPLOYED_CONTRACT"
echo "View on explorer: https://explorer-2.seismicdev.net/address/$DEPLOYED_CONTRACT"
